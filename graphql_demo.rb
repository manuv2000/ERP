# frozen_string_literal: true

require "json"
require_relative "lib/procurement/api/schema"
require_relative "lib/procurement/persistence/database"
require_relative "lib/procurement/persistence/sqlite_product_repository"

unless ARGV.size == 1
  abort "Usage: bundle exec ruby graphql_demo.rb PRODUCT_ID"
end

query = <<~GRAPHQL
  query FindProduct($id: ID!) {
    product(id: $id) {
      id
      sku
      name
    }
  }
GRAPHQL

database_path = File.join(__dir__, "db", "procurement.sqlite3")

Procurement::Persistence::Database.open(database_path) do |database|
  products =
    Procurement::Persistence::SQLiteProductRepository.new(database)

  result = Procurement::API::Schema.execute(
    query,
    variables: { "id" => ARGV.first },
    context: { products: products }
  )

  puts JSON.pretty_generate(result.to_h)
end
