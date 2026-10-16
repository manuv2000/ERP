# frozen_string_literal: true

require_relative "lib/procurement"
require_relative "lib/procurement/persistence/database"
require_relative "lib/procurement/persistence/sqlite_product_repository"
require_relative "lib/procurement/persistence/sqlite_purchase_order_repository"

module Procurement
  class DemoCLI
    USAGE = <<~TEXT
      Usage:
        bundle exec ruby cli.rb init
        bundle exec ruby cli.rb create-order ORDER_ID QUANTITY
        bundle exec ruby cli.rb receive ORDER_ID RECEIPT_ID QUANTITY
        bundle exec ruby cli.rb show ORDER_ID

      Demo product: product-001 / KEY-001 / USB keyboard
      Demo supplier reference: supplier-001
    TEXT

    def initialize(database, schema_path:)
      @database = database
      @schema_path = schema_path

      @products = Persistence::SQLiteProductRepository.new(database)
      @orders = Persistence::SQLitePurchaseOrderRepository.new(database)
    end

    def run(arguments)
      command, *values = arguments

      case command
      when "init"
        require_arguments!(values, 0)
        initialize_database
      when "create-order"
        require_arguments!(values, 2)
        create_order(values[0], parse_quantity(values[1]))
      when "receive"
        require_arguments!(values, 3)
        receive_goods(values[0], values[1], parse_quantity(values[2]))
      when "show"
        require_arguments!(values, 1)
        show_order(values[0])
      when "confirm"
        require_arguments!(values, 1)
        confirm_order(values[0])
      else
        raise ArgumentError, USAGE
      end
    end

    private

    def confirm_order(order_id)
      order = @orders.confirm(order_id)

      puts "Confirmed order #{order.id}."
      display_order(order)
    end

    def require_arguments!(values, expected_count)
      return if values.size == expected_count

      raise ArgumentError, USAGE
    end

    def parse_quantity(text)
      Integer(text, 10)
    rescue ArgumentError
      raise ArgumentError, "quantity must be a whole number"
    end

    def initialize_database
      @database.execute_batch(File.read(@schema_path))

      unless @products.find("product-001")
        @products.add(
          Product.new(
            id: "product-001",
            sku: "KEY-001",
            name: "USB keyboard"
          )
        )
      end

      puts "Database initialized; demo product is available."
    end

    def create_order(id, quantity)
      unless @products.find("product-001")
        raise ArgumentError, "demo product is missing; run init first"
      end

      order = PurchaseOrder.new(
        id: id,
        supplier_id: "supplier-001"
      )

      order.add_line(
        PurchaseOrderLine.new(
          id: "line-001",
          product_id: "product-001",
          ordered_quantity: quantity
        )
      )

      @orders.add(order)

      puts "Created draft order #{order.id} for #{quantity} units."
    end

    def receive_goods(order_id, receipt_id, quantity)
      receipt = GoodsReceipt.new(
        id: receipt_id,
        purchase_order_id: order_id,
        lines: [
          GoodsReceiptLine.new(
            purchase_order_line_id: "line-001",
            received_quantity: quantity
          )
        ]
      )

      order = @orders.record_receipt(order_id, receipt)

      puts "Recorded receipt #{receipt.id} for order #{order.id}."
      display_order(order)
    end

    def show_order(id)
      order = @orders.find(id)

      raise ArgumentError, "order does not exist" unless order

      display_order(order)
    end

    def display_order(order)
      puts "Order: #{order.id}"
      puts "Status: #{order.status}"
      puts "Supplier reference: #{order.supplier_id}"

      order.lines.each do |line|
        puts "Line: #{line.id} / Product: #{line.product_id}"
        puts "  Ordered: #{line.ordered_quantity}"
        puts "  Received: #{order.received_quantity_for(line.id)}"
        puts "  Outstanding: #{order.outstanding_quantity_for(line.id)}"
      end

      puts "Recorded receipts: #{order.receipts.size}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  database_path = File.join(__dir__, "db", "procurement.sqlite3")
  schema_path = File.join(__dir__, "db", "schema.sql")

  begin
    Procurement::Persistence::Database.open(database_path) do |database|
      Procurement::DemoCLI.new(
        database,
        schema_path: schema_path
      ).run(ARGV)
    end
  rescue ArgumentError, Procurement::PurchaseOrder::InvalidStateError => error
    warn "Error: #{error.message}"
    exit 1
  rescue SQLite3::ConstraintException => error
    warn "Database constraint rejected the operation: #{error.message}"
    exit 1
  rescue SQLite3::BusyException
    warn "Database is busy. Try the command again shortly."
    exit 1
  end
end
