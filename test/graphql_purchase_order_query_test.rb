# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/api/schema"
require_relative "../lib/procurement/persistence/sqlite_product_repository"
require_relative "../lib/procurement/persistence/sqlite_purchase_order_repository"
require_relative "../lib/procurement/application/receive_goods"
require_relative "../lib/procurement/persistence/sqlite_stock_movement_repository"

class GraphQLPurchaseOrderQueryTest < Minitest::Test
  QUERY = <<~GRAPHQL
    query FindOrder($id: ID!) {
      purchaseOrder(id: $id) {
        id
        status
        supplierId
        lines {
          id
          productId
          orderedQuantity
          receivedQuantity
          outstandingQuantity
        }
      }
    }
  GRAPHQL

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
    
    stock_movements =
      Procurement::Persistence::SQLiteStockMovementRepository.new(@database)

    transaction = lambda do |&operation|
      @database.transaction(:immediate, &operation)
    end

    @receive_goods = Procurement::Application::ReceiveGoods.new(
      orders: @orders,
      stock_movements: stock_movements,
      transaction: transaction
    )
    
    @products.add(
      Procurement::Product.new(
        id: "product-001",
        sku: "KEY-001",
        name: "USB keyboard"
      )
    )
  end

  def teardown
    @database&.close
  end

  def test_returns_order_details_and_partial_receiving_quantities
    store_order(id: "order-001", quantity: 10, received: 6)

    result = execute_query(
      QUERY,
      variables: { "id" => "order-001" }
    )

    refute result.key?("errors"), result["errors"].inspect

    assert_equal(
      {
        "id" => "order-001",
        "status" => "confirmed",
        "supplierId" => "supplier-001",
        "lines" => [
          {
            "id" => "line-001",
            "productId" => "product-001",
            "orderedQuantity" => 10,
            "receivedQuantity" => 6,
            "outstandingQuantity" => 4
          }
        ]
      },
      result.fetch("data").fetch("purchaseOrder")
    )
  end

  def test_returns_null_for_a_missing_order
    result = execute_query(
      QUERY,
      variables: { "id" => "missing-order" }
    )

    refute result.key?("errors"), result["errors"].inspect
    assert_nil result.fetch("data").fetch("purchaseOrder")
  end

  def test_returns_zero_received_when_there_are_no_receipts
    store_order(id: "order-001", quantity: 10)

    result = execute_query(
      QUERY,
      variables: { "id" => "order-001" }
    )

    refute result.key?("errors"), result["errors"].inspect

    line = result.fetch("data")
                 .fetch("purchaseOrder")
                 .fetch("lines")
                 .first

    assert_equal 0, line.fetch("receivedQuantity")
    assert_equal 10, line.fetch("outstandingQuantity")
  end

  def test_keeps_quantities_separate_for_two_orders_in_one_query
    store_order(id: "order-001", quantity: 10, received: 6)
    store_order(id: "order-002", quantity: 20, received: 3)

    query = <<~GRAPHQL
      {
        first: purchaseOrder(id: "order-001") {
          lines {
            receivedQuantity
            outstandingQuantity
          }
        }

        second: purchaseOrder(id: "order-002") {
          lines {
            receivedQuantity
            outstandingQuantity
          }
        }
      }
    GRAPHQL

    result = execute_query(query)

    refute result.key?("errors"), result["errors"].inspect

    data = result.fetch("data")

    assert_equal(
      {
        "receivedQuantity" => 6,
        "outstandingQuantity" => 4
      },
      data.fetch("first").fetch("lines").first
    )

    assert_equal(
      {
        "receivedQuantity" => 3,
        "outstandingQuantity" => 17
      },
      data.fetch("second").fetch("lines").first
    )
  end

  private

  def execute_query(query, variables: {})
    Procurement::API::Schema.execute(
      query,
      variables: variables,
      context: { orders: @orders }
    ).to_h
  end

  def store_order(id:, quantity:, received: nil)
    order = Procurement::PurchaseOrder.new(
      id: id,
      supplier_id: "supplier-001"
    )

    order.add_line(
      Procurement::PurchaseOrderLine.new(
        id: "line-001",
        product_id: "product-001",
        ordered_quantity: quantity
      )
    )

    order.confirm!
    @orders.add(order)

    return unless received

    receipt = Procurement::GoodsReceipt.new(
      id: "receipt-001",
      purchase_order_id: id,
      lines: [
        Procurement::GoodsReceiptLine.new(
          purchase_order_line_id: "line-001",
          received_quantity: received
        )
      ]
    )

    @receive_goods.call(order_id: id, receipt: receipt)
  end
end
