# frozen_string_literal: true

require "json"
require_relative "lib/procurement/api/schema"
require_relative "lib/procurement/persistence/database"
require_relative "lib/procurement/persistence/sqlite_purchase_order_repository"

unless ARGV.size == 1
  abort "Usage: bundle exec ruby graphql_order_demo.rb ORDER_ID"
end

query = <<~GRAPHQL
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

database_path = File.join(__dir__, "db", "procurement.sqlite3")

Procurement::Persistence::Database.open(database_path) do |database|
  orders =
    Procurement::Persistence::SQLitePurchaseOrderRepository.new(database)

  result = Procurement::API::Schema.execute(
    query,
    variables: { "id" => ARGV.first },
    context: { orders: orders }
  )

  puts JSON.pretty_generate(result.to_h)
end
