require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "rack/mock"

require_relative "../lib/procurement/api/http_app"

class HttpReceiptIntegrationTest < Minitest::Test
  MUTATION = <<~GRAPHQL.freeze
    mutation ReceiveGoods($input: RecordGoodsReceiptInput!) {
      recordGoodsReceipt(input: $input) {
        order {
          id
        }
        errors
      }
    }
  GRAPHQL

  def setup
    @temporary_directory = Dir.mktmpdir("procurement-test-")
    @database_path = File.join(@temporary_directory, "test.sqlite3")

    seed_database

    app = Procurement::API::HttpApp.new(
      database_path: @database_path,
      logger: Logger.new(StringIO.new)
    )

    @request = Rack::MockRequest.new(app)
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory
  end

  def test_records_a_receipt_once_and_accepts_an_identical_retry
    response = submit_receipt

    assert_equal 200, response.status

    payload = JSON.parse(response.body)
                  .fetch("data")
                  .fetch("recordGoodsReceipt")

    assert_empty payload.fetch("errors")
    assert_equal "order-http-test", payload.fetch("order").fetch("id")

    order = reload_order

    assert_equal 6, order.received_quantity_for("line-001")
    assert_equal 4, order.outstanding_quantity_for("line-001")
    assert_equal 1, order.receipts.size

    duplicate_response = submit_receipt

    assert_equal 200, duplicate_response.status

    duplicate_payload = JSON.parse(duplicate_response.body)
                            .fetch("data")
                            .fetch("recordGoodsReceipt")

    assert_empty duplicate_payload.fetch("errors")
    assert_equal(
      "order-http-test",
      duplicate_payload.fetch("order").fetch("id")
    )

    unchanged_order = reload_order

    assert_equal 6, unchanged_order.received_quantity_for("line-001")
    assert_equal 4, unchanged_order.outstanding_quantity_for("line-001")
    assert_equal 1, unchanged_order.receipts.size
  end

  def test_product_query_reports_stock_after_receiving_goods
    receipt_response = submit_receipt

    assert_equal 200, receipt_response.status

    receipt_payload = JSON.parse(receipt_response.body)
                          .fetch("data")
                          .fetch("recordGoodsReceipt")

    assert_empty receipt_payload.fetch("errors")

    query = <<~GRAPHQL
      query ProductStock($id: ID!) {
        product(id: $id) {
          id
          quantityOnHand
        }
      }
    GRAPHQL

    response = @request.post(
      "/graphql",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(
        query: query,
        variables: { id: "product-001" }
      )
    )

    assert_equal 200, response.status

    result = JSON.parse(response.body)

    refute result.key?("errors"), result.inspect

    product = result.fetch("data").fetch("product")

    assert_equal "product-001", product.fetch("id")
    assert_equal 6, product.fetch("quantityOnHand")
  end

  def test_product_query_reports_zero_before_any_receipts
    response = @request.post(
      "/graphql",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(
        query: <<~GRAPHQL
          {
            product(id: "product-001") {
              quantityOnHand
            }
          }
        GRAPHQL
      )
    )

    assert_equal 200, response.status

    result = JSON.parse(response.body)

    refute result.key?("errors"), result.inspect

    assert_equal(
      0,
      result.fetch("data")
            .fetch("product")
            .fetch("quantityOnHand")
    )
  end

  private

  def seed_database
    schema_path = File.expand_path("../db/schema.sql", __dir__)

    Procurement::Persistence::Database.open(@database_path) do |database|
      database.execute_batch(File.read(schema_path))

      products =
        Procurement::Persistence::SQLiteProductRepository.new(database)

      orders =
        Procurement::Persistence::SQLitePurchaseOrderRepository.new(database)

      products.add(
        Procurement::Product.new(
          id: "product-001",
          sku: "KEY-001",
          name: "USB keyboard"
        )
      )

      order = Procurement::PurchaseOrder.new(
        id: "order-http-test",
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
      orders.add(order)
    end
  end

  def submit_receipt
    body = JSON.generate(
      query: MUTATION,
      variables: {
        input: {
          purchaseOrderId: "order-http-test",
          receiptId: "receipt-http-test",
          lines: [
            {
              purchaseOrderLineId: "line-001",
              receivedQuantity: 6
            }
          ]
        }
      }
    )

    @request.post(
      "/graphql",
      "CONTENT_TYPE" => "application/json",
      input: body
    )
  end

  def reload_order
    Procurement::Persistence::Database.open(@database_path) do |database|
      repository =
        Procurement::Persistence::SQLitePurchaseOrderRepository.new(database)

      repository.find("order-http-test")
    end
  end
end
