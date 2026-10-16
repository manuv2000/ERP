# frozen_string_literal: true

require "sqlite3"
require_relative "../product"

module Procurement
  module Persistence
    class SQLiteProductRepository
      def initialize(database)
        @database = database
      end

      def add(product)
        unless product.is_a?(Product)
          raise ArgumentError, "product must be a Product"
        end

        @database.execute(
          "INSERT INTO products (id, sku, name) VALUES (?, ?, ?)",
          [product.id, product.sku, product.name]
        )

        product
      end

      def find(id)
        row = @database.get_first_row(
          "SELECT id, sku, name FROM products WHERE id = ?",
          [id]
        )

        return nil unless row

        Product.new(
          id: row.fetch("id"),
          sku: row.fetch("sku"),
          name: row.fetch("name")
        )
      end
    end
  end
end
