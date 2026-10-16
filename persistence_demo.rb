# frozen_string_literal: true

require_relative "lib/procurement"
require_relative "lib/procurement/persistence/sqlite_product_repository"

command = ARGV.first

unless %w[save load].include?(command)
  abort "Usage: bundle exec ruby persistence_demo.rb save|load"
end

database_path = File.join(__dir__, "db", "procurement.sqlite3")
schema_path = File.join(__dir__, "db", "schema.sql")

database = SQLite3::Database.new(database_path)

begin
  database.execute("PRAGMA foreign_keys = ON")
  database.results_as_hash = true
  database.execute_batch(File.read(schema_path))

  repository = Procurement::Persistence::SQLiteProductRepository.new(database)

  case command
  when "save"
    product = Procurement::Product.new(
      id: "product-001",
      sku: "KEY-001",
      name: "USB keyboard"
    )

    repository.add(product)

    puts "Saved: #{product.sku} — #{product.name}"
  when "load"
    product = repository.find("product-001")

    if product
      puts "Loaded: #{product.sku} — #{product.name}"
    else
      puts "Product not found"
    end
  end
ensure
  database.close
end
