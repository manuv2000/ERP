# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/api/schema"
require_relative "../lib/procurement/persistence/sqlite_product_repository"
require_relative "../lib/procurement/persistence/sqlite_purchase_order_repository"

class GraphQLConfirmPurchaseOrderTest < Minitest::Test
  MUTATION = <<~GRAPHQL
    mutation ConfirmOrder($id: ID!) {
      confirmPurchaseOrder(id: $id) {
        order {
          id
          status
        }
        errors
      }
    }
  GRAPHQL

  def setup
    @database = SQLite3::Database.new(":memory:")
    @database.results_as_hash = true
    @database.execute("PRAGMA foreign_keys = ON")

    schema_path = File.join(__dir__, "..", "db", "schema.sql")
    @database.execute_batch(File.read(schema_path))

    products =
      Procurement::Persistence::SQLiteProductRepository.new(@database)

    products.add(
      Procurement::Product.new(
        id: "product-001",
        sku: "KEY-001",
        name: "USB keyboard"
      )
    )

    @orders =
      Procurement::Persistence::SQLitePurchaseOrderRepository.new(@database)
  end

  def teardown
    @database&.close
  end

  def test_confirms_and_persists_a_draft
    store_order

    payload = execute_confirmation("order-001")

    assert_equal(
      { "id" => "order-001", "status" => "confirmed" },
      payload.fetch("order")
    )
    assert_equal [], payload.fetch("errors")
    assert_equal :confirmed, @orders.find("order-001").status
  end

  def test_returns_a_business_error_for_an_empty_order
    store_order(with_line: false)

    payload = execute_confirmation("order-001")

    assert_nil payload.fetch("order")
    assert_equal(
      ["cannot confirm an empty order"],
      payload.fetch("errors")
    )
    assert_equal :draft, @orders.find("order-001").status
  end

  def test_returns_a_business_error_for_repeated_confirmation
    store_order
    @orders.confirm("order-001")

    payload = execute_confirmation("order-001")

    assert_nil payload.fetch("order")
    assert_equal ["order must be a draft"], payload.fetch("errors")
    assert_equal :confirmed, @orders.find("order-001").status
  end

  def test_returns_a_business_error_for_a_missing_order
    payload = execute_confirmation("missing-order")

    assert_nil payload.fetch("order")
    assert_equal ["order does not exist"], payload.fetch("errors")
  end

  private

  def execute_confirmation(id)
    result = Procurement::API::Schema.execute(
      MUTATION,
      variables: { "id" => id },
      context: { orders: @orders }
    ).to_h

    refute result.key?("errors"), result["errors"].inspect

    result.fetch("data").fetch("confirmPurchaseOrder")
  end

  def store_order(with_line: true)
    order = Procurement::PurchaseOrder.new(
      id: "order-001",
      supplier_id: "supplier-001"
    )

    if with_line
      order.add_line(
        Procurement::PurchaseOrderLine.new(
          id: "line-001",
          product_id: "product-001",
          ordered_quantity: 10
        )
      )
    end

    @orders.add(order)
  end
end
