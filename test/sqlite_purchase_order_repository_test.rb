# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/persistence/sqlite_product_repository"
require_relative "../lib/procurement/persistence/sqlite_purchase_order_repository"

class SQLitePurchaseOrderRepositoryTest < Minitest::Test
  def setup
    @database = SQLite3::Database.new(":memory:")
    @database.results_as_hash = true
    @database.execute("PRAGMA foreign_keys = ON")

    schema_path = File.join(__dir__, "..", "db", "schema.sql")
    @database.execute_batch(File.read(schema_path))

    @products =
      Procurement::Persistence::SQLiteProductRepository.new(@database)

    @orders =
      Procurement::Persistence::SQLitePurchaseOrderRepository.new(@database)

    @products.add(
      Procurement::Product.new(
        id: "product-001",
        sku: "KEY-001",
        name: "USB keyboard"
      )
    )

    @products.add(
      Procurement::Product.new(
        id: "product-002",
        sku: "MOU-001",
        name: "USB mouse"
      )
    )
  end

  def teardown
    @database.close
  end

  def test_loads_a_confirmed_order_and_preserves_line_order
    order = build_order
    order.add_line(
      build_line(id: "line-002", product_id: "product-002")
    )
    order.confirm!

    @orders.add(order)
    loaded = @orders.find(order.id)

    refute_same order, loaded
    assert_equal "supplier-001", loaded.supplier_id
    assert_equal :confirmed, loaded.status
    assert_equal ["line-001", "line-002"], loaded.lines.map(&:id)
    assert_equal ["product-001", "product-002"],
                 loaded.lines.map(&:product_id)
    assert_equal [10, 10], loaded.lines.map(&:ordered_quantity)
  end

  def test_preserves_draft_status
    @orders.add(build_order)

    assert_equal :draft, @orders.find("order-001").status
  end

  def test_returns_nil_for_an_unknown_order
    assert_nil @orders.find("missing-order")
  end

  def test_rolls_back_order_and_earlier_lines_if_a_later_line_fails
    order = build_order
    order.add_line(
      build_line(id: "line-002", product_id: "missing-product")
    )

    assert_raises(SQLite3::ConstraintException) do
      @orders.add(order)
    end

    assert_nil @orders.find(order.id)

    line_count = @database.get_first_value(
      "SELECT COUNT(*) FROM purchase_order_lines
       WHERE purchase_order_id = ?",
      [order.id]
    )

    assert_equal 0, line_count

    # Previously committed products must remain.
    refute_nil @products.find("product-001")
  end

  def test_rejects_orders_with_receipts_before_saving
    order = build_order
    order.confirm!

    order.record_receipt(
      Procurement::GoodsReceipt.new(
        id: "receipt-001",
        purchase_order_id: order.id,
        lines: [
          Procurement::GoodsReceiptLine.new(
            purchase_order_line_id: "line-001",
            received_quantity: 6
          )
        ]
      )
    )

    assert_raises(ArgumentError) do
      @orders.add(order)
    end

    assert_nil @orders.find(order.id)
  end

  def test_restores_received_and_outstanding_quantities
    order = build_order
    order.confirm!
    @orders.add(order)

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 6)
    )

    loaded = @orders.find(order.id)

    assert_equal 1, loaded.receipts.size
    assert_equal 6, loaded.received_quantity_for("line-001")
    assert_equal 4, loaded.outstanding_quantity_for("line-001")
  end

  def test_checks_new_receipts_against_saved_deliveries
    order = build_order
    order.confirm!
    @orders.add(order)

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 6)
    )

    assert_raises(ArgumentError) do
      @orders.record_receipt(
        order.id,
        build_receipt(id: "receipt-002", quantity: 5)
      )
    end

    loaded = @orders.find(order.id)

    assert_equal 1, loaded.receipts.size
    assert_equal 6, loaded.received_quantity_for("line-001")
  end

  def test_identical_retry_does_not_add_receipts_or_stock
    order = build_order
    order.confirm!
    @orders.add(order)

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 10)
    )

    retried_order = @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 10)
    )

    assert_equal order.id, retried_order.id
    assert_equal 1, retried_order.receipts.size
    assert_equal 10, retried_order.received_quantity_for("line-001")

    loaded = @orders.find(order.id)

    assert_equal 1, loaded.receipts.size
    assert_equal 0, loaded.outstanding_quantity_for("line-001")

    stock =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    assert_equal 10, stock.quantity_on_hand("product-001")
    assert_equal 1, @database.get_first_value(
      "SELECT COUNT(*) FROM stock_movements"
    )
  end

  def test_confirms_a_stored_draft
    @orders.add(build_order)

    @orders.confirm("order-001")

    loaded = @orders.find("order-001")

    assert_equal :confirmed, loaded.status
    assert_equal 1, loaded.lines.size
    assert_equal 10, loaded.lines.first.ordered_quantity
  end

  def test_cannot_confirm_a_stored_empty_order
    order = Procurement::PurchaseOrder.new(
      id: "empty-order",
      supplier_id: "supplier-001"
    )

    @orders.add(order)

    assert_raises(Procurement::PurchaseOrder::InvalidStateError) do
      @orders.confirm(order.id)
    end

    assert_equal :draft, @orders.find(order.id).status
  end

  def test_cannot_confirm_a_stored_order_twice
    @orders.add(build_order)
    @orders.confirm("order-001")

    assert_raises(Procurement::PurchaseOrder::InvalidStateError) do
      @orders.confirm("order-001")
    end

    assert_equal :confirmed, @orders.find("order-001").status
  end

  def test_cannot_confirm_a_missing_order
    assert_raises(Procurement::OrderNotFoundError) do
      @orders.confirm("missing-order")
    end
  end

  def test_rolls_back_receipt_and_movements_if_a_later_movement_fails
    order = build_order
    order.add_line(
      build_line(id: "line-002", product_id: "product-002")
    )
    order.confirm!
    @orders.add(order)

    @database.execute_batch(<<~SQL)
      CREATE TEMP TRIGGER reject_second_product_movement
      BEFORE INSERT ON main.stock_movements
      WHEN NEW.product_id = 'product-002'
      BEGIN
        SELECT RAISE(ABORT, 'simulated inventory failure');
      END;
    SQL

    receipt = Procurement::GoodsReceipt.new(
      id: "receipt-001",
      purchase_order_id: order.id,
      lines: [
        Procurement::GoodsReceiptLine.new(
          purchase_order_line_id: "line-001",
          received_quantity: 6
        ),
        Procurement::GoodsReceiptLine.new(
          purchase_order_line_id: "line-002",
          received_quantity: 3
        )
      ]
    )

    error = assert_raises(SQLite3::ConstraintException) do
      @orders.record_receipt(order.id, receipt)
    end

    assert_includes error.message, "simulated inventory failure"

    assert_equal 0, @database.get_first_value(
      "SELECT COUNT(*) FROM goods_receipts"
    )
    assert_equal 0, @database.get_first_value(
      "SELECT COUNT(*) FROM goods_receipt_lines"
    )
    assert_equal 0, @database.get_first_value(
      "SELECT COUNT(*) FROM stock_movements"
    )

    loaded = @orders.find(order.id)

    assert_equal :confirmed, loaded.status
    assert_equal 2, loaded.lines.size
    assert_empty loaded.receipts
    assert_equal 0, loaded.received_quantity_for("line-001")
    assert_equal 0, loaded.received_quantity_for("line-002")
  end

  def test_recording_a_receipt_increases_stock
    order = build_order
    order.confirm!
    @orders.add(order)

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 6)
    )

    stock =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    assert_equal 6, stock.quantity_on_hand("product-001")
    assert_equal 0, stock.quantity_on_hand("product-002")

    loaded = @orders.find(order.id)

    assert_equal 6, loaded.received_quantity_for("line-001")
    assert_equal 1, loaded.receipts.size
  end

  def test_rejects_receipt_id_reuse_with_different_contents
    order = build_order
    order.confirm!
    @orders.add(order)

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 3)
    )

    error = assert_raises(Procurement::ReceiptConflictError) do
      @orders.record_receipt(
        order.id,
        build_receipt(id: "receipt-001", quantity: 4)
      )
    end

    assert_equal(
      "receipt id already exists with different contents",
      error.message
    )

    loaded = @orders.find(order.id)

    assert_equal 1, loaded.receipts.size
    assert_equal 3, loaded.received_quantity_for("line-001")

    stock =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    assert_equal 3, stock.quantity_on_hand("product-001")
  end

  def test_retry_returns_current_order_after_a_later_delivery
    order = build_order
    order.confirm!
    @orders.add(order)

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 6)
    )

    @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-002", quantity: 4)
    )

    retried_order = @orders.record_receipt(
      order.id,
      build_receipt(id: "receipt-001", quantity: 6)
    )

    assert_equal 2, retried_order.receipts.size
    assert_equal 10, retried_order.received_quantity_for("line-001")
    assert_equal 0, retried_order.outstanding_quantity_for("line-001")

    stock =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    assert_equal 10, stock.quantity_on_hand("product-001")
    assert_equal 2, @database.get_first_value(
      "SELECT COUNT(*) FROM stock_movements"
    )
  end

  def test_retry_accepts_reordered_lines_without_adding_stock
    order = build_order
    order.add_line(
      build_line(id: "line-002", product_id: "product-002")
    )
    order.confirm!
    @orders.add(order)

    original = Procurement::GoodsReceipt.new(
      id: "receipt-001",
      purchase_order_id: order.id,
      lines: [
        Procurement::GoodsReceiptLine.new(
          purchase_order_line_id: "line-001",
          received_quantity: 6
        ),
        Procurement::GoodsReceiptLine.new(
          purchase_order_line_id: "line-002",
          received_quantity: 3
        )
      ]
    )

    @orders.record_receipt(order.id, original)

    reordered = Procurement::GoodsReceipt.new(
      id: original.id,
      purchase_order_id: order.id,
      lines: original.lines.reverse
    )

    @orders.record_receipt(order.id, reordered)

    loaded = @orders.find(order.id)

    assert_equal 1, loaded.receipts.size
    assert_equal 6, loaded.received_quantity_for("line-001")
    assert_equal 3, loaded.received_quantity_for("line-002")

    stock =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    assert_equal 6, stock.quantity_on_hand("product-001")
    assert_equal 3, stock.quantity_on_hand("product-002")
    assert_equal 2, @database.get_first_value(
      "SELECT COUNT(*) FROM stock_movements"
    )
  end
  
  private

  def build_receipt(id:, quantity:)
    Procurement::GoodsReceipt.new(
      id: id,
      purchase_order_id: "order-001",
      lines: [
        Procurement::GoodsReceiptLine.new(
          purchase_order_line_id: "line-001",
          received_quantity: quantity
        )
      ]
    )
  end

  def build_order
    order = Procurement::PurchaseOrder.new(
      id: "order-001",
      supplier_id: "supplier-001"
    )

    order.add_line(build_line)
    order
  end

  def build_line(id: "line-001", product_id: "product-001")
    Procurement::PurchaseOrderLine.new(
      id: id,
      product_id: product_id,
      ordered_quantity: 10
    )
  end
end
