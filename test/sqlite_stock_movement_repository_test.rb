# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/persistence/sqlite_stock_movement_repository"
require_relative "../lib/procurement/persistence/inventory_upgrade"

class SQLiteStockMovementRepositoryTest < Minitest::Test
  def setup
    @database = SQLite3::Database.new(":memory:")
    @database.results_as_hash = true
    @database.execute("PRAGMA foreign_keys = ON")

    schema_path = File.expand_path("../db/schema.sql", __dir__)
    @database.execute_batch(File.read(schema_path))

    @repository =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    seed_receipt
  end

  def teardown
    @database&.close
  end

  def test_returns_zero_before_any_movements_exist
    assert_equal 0, @repository.quantity_on_hand("product-001")
  end

  def test_saves_a_movement_and_calculates_stock
    @repository.add(build_movement)

    assert_equal 6, @repository.quantity_on_hand("product-001")
  end

  def test_rejects_duplicate_source_without_increasing_stock
    @repository.add(build_movement)

    assert_raises(SQLite3::ConstraintException) do
      @repository.add(build_movement)
    end

    assert_equal 6, @repository.quantity_on_hand("product-001")
  end

  def test_rejects_a_movement_without_a_source_receipt_line
    assert_raises(SQLite3::ConstraintException) do
      @repository.add(build_movement(receipt_id: "missing-receipt"))
    end

    assert_equal 0, @repository.quantity_on_hand("product-001")
  end

  def test_treats_sql_like_product_id_as_literal_data
    @repository.add(build_movement)

    suspicious_id = "' OR 1=1 -- "

    assert_equal 0, @repository.quantity_on_hand(suspicious_id)
    assert_equal 6, @repository.quantity_on_hand("product-001")
  end

  def test_upgrade_creates_table_and_backfills_existing_receipts_once
    @database.execute("DROP TABLE stock_movements")

    upgrade = Procurement::Persistence::InventoryUpgrade.new(
      @database,
      schema_path: File.expand_path("../db/schema.sql", __dir__)
    )

    assert_equal 1, upgrade.run
    assert_equal 6, @repository.quantity_on_hand("product-001")

    assert_equal 0, upgrade.run
    assert_equal 6, @repository.quantity_on_hand("product-001")

    assert_equal 1, @database.get_first_value(
      "SELECT COUNT(*) FROM stock_movements"
    )
  end

  def test_upgrade_rejects_conflicting_existing_movements_and_rolls_back
    @repository.add(build_movement)

    @database.execute(
      "UPDATE stock_movements SET quantity = ?",
      [5]
    )

    @database.execute(
      "INSERT INTO goods_receipts (purchase_order_id, id)
      VALUES (?, ?)",
      ["order-001", "receipt-002"]
    )

    @database.execute(
      "INSERT INTO goods_receipt_lines
        (purchase_order_id, receipt_id, purchase_order_line_id,
          received_quantity, position)
      VALUES (?, ?, ?, ?, ?)",
      ["order-001", "receipt-002", "line-001", 2, 0]
    )

    upgrade = Procurement::Persistence::InventoryUpgrade.new(
      @database,
      schema_path: File.expand_path("../db/schema.sql", __dir__)
    )

    error = assert_raises(RuntimeError) { upgrade.run }

    assert_includes error.message, "movements disagree with receipts"

    assert_equal 1, @database.get_first_value(
      "SELECT COUNT(*) FROM stock_movements"
    )
    assert_equal 5, @repository.quantity_on_hand("product-001")
  end
  
  private

  def build_movement(receipt_id: "receipt-001")
    Procurement::StockMovement.new(
      product_id: "product-001",
      quantity: 6,
      purchase_order_id: "order-001",
      receipt_id: receipt_id,
      purchase_order_line_id: "line-001"
    )
  end

  def seed_receipt
    @database.execute_batch(<<~SQL)
      INSERT INTO products (id, sku, name)
      VALUES ('product-001', 'KEY-001', 'USB keyboard');

      INSERT INTO purchase_orders (id, supplier_id, status)
      VALUES ('order-001', 'supplier-001', 'confirmed');

      INSERT INTO purchase_order_lines
        (purchase_order_id, id, product_id, ordered_quantity, position)
      VALUES ('order-001', 'line-001', 'product-001', 10, 0);

      INSERT INTO goods_receipts (purchase_order_id, id)
      VALUES ('order-001', 'receipt-001');

      INSERT INTO goods_receipt_lines
        (purchase_order_id, receipt_id, purchase_order_line_id,
         received_quantity, position)
      VALUES ('order-001', 'receipt-001', 'line-001', 6, 0);
    SQL
  end
end
