# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/api/schema"
require_relative "../lib/procurement/persistence/sqlite_product_repository"
require_relative "../lib/procurement/persistence/sqlite_purchase_order_repository"

class GraphQLRecordGoodsReceiptTest < Minitest::Test
  MUTATION = <<~GRAPHQL
    mutation ReceiveGoods($input: RecordGoodsReceiptInput!) {
      recordGoodsReceipt(input: $input) {
        order {
          id
          lines {
            id
            receivedQuantity
            outstandingQuantity
          }
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

    order = Procurement::PurchaseOrder.new(
      id: "order-001",
      supplier_id: "supplier-001"
    )

    order.add_line(
      Procurement::PurchaseOrderLine.new(
        id: "line-001",
        product_id: "product-001",
        ordered_quantity: 10
      )
    )

    order.confirm!
    @orders.add(order)
  end

  def teardown
    @database&.close
  end

  def test_records_and_persists_a_partial_delivery
    payload = receive(lines: [input_line(quantity: 6)])

    assert_equal [], payload.fetch("errors")
    assert_equal(
      {
        "id" => "line-001",
        "receivedQuantity" => 6,
        "outstandingQuantity" => 4
      },
      payload.fetch("order").fetch("lines").first
    )

    assert_equal 6,
                 @orders.find("order-001").received_quantity_for("line-001")
  end

  def test_rejects_over_delivery_without_saving_it
    receive(lines: [input_line(quantity: 6)])

    payload = receive(
      receipt_id: "receipt-002",
      lines: [input_line(quantity: 5)]
    )

    assert_nil payload.fetch("order")
    assert_equal(
      ["received quantity exceeds outstanding quantity"],
      payload.fetch("errors")
    )

    loaded = @orders.find("order-001")
    assert_equal 1, loaded.receipts.size
    assert_equal 6, loaded.received_quantity_for("line-001")
  end

  def test_rejects_an_empty_receipt
    payload = receive(lines: [])

    assert_nil payload.fetch("order")
    assert_equal(
      ["lines must be a non-empty Array"],
      payload.fetch("errors")
    )
    assert_equal [], @orders.find("order-001").receipts
  end

  def test_rejects_zero_quantity
    payload = receive(lines: [input_line(quantity: 0)])

    assert_nil payload.fetch("order")
    assert_equal(
      ["received_quantity must be a positive Integer"],
      payload.fetch("errors")
    )
    assert_equal [], @orders.find("order-001").receipts
  end

  def test_rejects_the_entire_receipt_if_one_line_is_unknown
    payload = receive(
      lines: [
        input_line(quantity: 3),
        input_line(quantity: 1, order_line_id: "unknown-line")
      ]
    )

    assert_nil payload.fetch("order")
    assert_equal ["order line does not exist"], payload.fetch("errors")
    assert_equal [], @orders.find("order-001").receipts
  end

  def test_rejects_duplicate_receipt_recording
    receive(lines: [input_line(quantity: 3)])
    payload = receive(lines: [input_line(quantity: 3)])

    assert_nil payload.fetch("order")
    assert_equal(
      ["receipt has already been recorded"],
      payload.fetch("errors")
    )

    loaded = @orders.find("order-001")
    assert_equal 1, loaded.receipts.size
    assert_equal 3, loaded.received_quantity_for("line-001")
  end

  def test_records_multiple_lines_in_one_receipt
    products =
      Procurement::Persistence::SQLiteProductRepository.new(@database)

    products.add(
      Procurement::Product.new(
        id: "product-002",
        sku: "MOU-001",
        name: "USB mouse"
      )
    )

    order = Procurement::PurchaseOrder.new(
      id: "order-multiple",
      supplier_id: "supplier-001"
    )

    order.add_line(
      Procurement::PurchaseOrderLine.new(
        id: "keyboard-line",
        product_id: "product-001",
        ordered_quantity: 10
      )
    )

    order.add_line(
      Procurement::PurchaseOrderLine.new(
        id: "mouse-line",
        product_id: "product-002",
        ordered_quantity: 8
      )
    )

    order.confirm!
    @orders.add(order)

    payload = receive(
      order_id: order.id,
      lines: [
        input_line(quantity: 6, order_line_id: "keyboard-line"),
        input_line(quantity: 3, order_line_id: "mouse-line")
      ]
    )

    assert_equal [], payload.fetch("errors")

    assert_equal(
      [
        {
          "id" => "keyboard-line",
          "receivedQuantity" => 6,
          "outstandingQuantity" => 4
        },
        {
          "id" => "mouse-line",
          "receivedQuantity" => 3,
          "outstandingQuantity" => 5
        }
      ],
      payload.fetch("order").fetch("lines")
    )

    loaded = @orders.find(order.id)

    assert_equal 1, loaded.receipts.size
    assert_equal 2, loaded.receipts.first.lines.size
    assert_equal 6, loaded.received_quantity_for("keyboard-line")
    assert_equal 3, loaded.received_quantity_for("mouse-line")
  end

  def test_does_not_hide_unexpected_repository_errors
    broken_repository = Object.new

    def broken_repository.record_receipt(_order_id, _receipt)
      raise ArgumentError, "unexpected repository bug"
    end

    error = assert_raises(ArgumentError) do
      Procurement::API::Schema.execute(
        MUTATION,
        variables: {
          "input" => {
            "purchaseOrderId" => "order-001",
            "receiptId" => "receipt-001",
            "lines" => [input_line(quantity: 3)]
          }
        },
        context: { orders: broken_repository }
      )
    end

    assert_equal "unexpected repository bug", error.message
  end
  
  private

  def receive(
    lines:,
    receipt_id: "receipt-001",
    order_id: "order-001"
  )
    result = Procurement::API::Schema.execute(
      MUTATION,
      variables: {
        "input" => {
          "purchaseOrderId" => order_id,
          "receiptId" => receipt_id,
          "lines" => lines
        }
      },
      context: { orders: @orders }
    ).to_h

    refute result.key?("errors"), result["errors"].inspect

    result.fetch("data").fetch("recordGoodsReceipt")
  end

  def input_line(quantity:, order_line_id: "line-001")
    {
      "purchaseOrderLineId" => order_line_id,
      "receivedQuantity" => quantity
    }
  end
end