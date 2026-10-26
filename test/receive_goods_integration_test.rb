# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/application/receive_goods"
require_relative "../lib/procurement/persistence/sqlite_product_repository"
require_relative "../lib/procurement/persistence/sqlite_purchase_order_repository"
require_relative "../lib/procurement/persistence/sqlite_stock_movement_repository"

class ReceiveGoodsIntegrationTest < Minitest::Test
  # Setup, teardown and tests go here.
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

    @stock_movements =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    transaction = lambda do |&operation|
      @database.transaction(:immediate, &operation)
    end

    @receive_goods = Procurement::Application::ReceiveGoods.new(
      orders: @orders,
      stock_movements: @stock_movements,
      transaction: transaction
    )

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

  def test_restores_received_and_outstanding_quantities
    order = build_order
    order.confirm!
    @orders.add(order)

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 6)
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

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 6)
    )

    assert_raises(ArgumentError) do
      @receive_goods.call(
        order_id: order.id,
        receipt: build_receipt(id: "receipt-001", quantity: 5)
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

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 10)
    )

    retried_order = @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 10)
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
      @receive_goods.call(order_id: order.id, receipt: receipt)
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

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 6)
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

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 3)
    )

    error = assert_raises(Procurement::ReceiptConflictError) do
      @receive_goods.call(
        order_id: order.id,
        receipt: build_receipt(id: "receipt-001", quantity: 4)
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

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 6)
    )

    @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-002", quantity: 4)
    )

    retried_order = @receive_goods.call(
      order_id: order.id,
      receipt: build_receipt(id: "receipt-001", quantity: 6)
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

    @receive_goods.call(order_id: order.id, receipt: original)

    reordered = Procurement::GoodsReceipt.new(
      id: original.id,
      purchase_order_id: order.id,
      lines: original.lines.reverse
    )

    @receive_goods.call(order_id: order.id, receipt: reordered)

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

  def test_rolls_back_receipt_when_a_line_insert_fails
    order = build_order
    order.confirm!
    @orders.add(order)

    @database.execute_batch(<<~SQL)
      CREATE TEMP TRIGGER reject_receipt_line
      BEFORE INSERT ON goods_receipt_lines
      BEGIN
        SELECT RAISE(ABORT, 'simulated write failure');
      END;
    SQL

    assert_raises(SQLite3::ConstraintException) do
      @receive_goods.call(
        order_id: order.id,
        receipt: build_receipt(id: "receipt-001", quantity: 6)
      )
    end

    loaded = @orders.find(order.id)

    assert_equal [], loaded.receipts
    assert_equal 0, loaded.received_quantity_for("line-001")
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
