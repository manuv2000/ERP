# frozen_string_literal: true

require "sqlite3"
require_relative "../stock_movement"

module Procurement
  module Persistence
    class SQLiteStockMovementRepository
      def initialize(database)
        @database = database
      end

      def add(movement)
        unless movement.is_a?(StockMovement)
          raise ArgumentError, "movement must be a StockMovement"
        end

        @database.execute(
          "INSERT INTO stock_movements
             (purchase_order_id, receipt_id, purchase_order_line_id,
              product_id, quantity)
           VALUES (?, ?, ?, ?, ?)",
          [
            movement.purchase_order_id,
            movement.receipt_id,
            movement.purchase_order_line_id,
            movement.product_id,
            movement.quantity
          ]
        )

        movement
      end

      def quantity_on_hand(product_id)
        @database.get_first_value(
          "SELECT COALESCE(SUM(quantity), 0)
           FROM stock_movements
           WHERE product_id = ?",
          [product_id]
        )
      end
    end
  end
end
