# frozen_string_literal: true

module Procurement
  module Persistence
    class InventoryUpgrade
      def initialize(database, schema_path:)
        @database = database
        @schema_path = schema_path
      end

      def run
        inserted_count = 0

        @database.transaction(:immediate) do
          @database.execute_batch(File.read(@schema_path))

          @database.execute(<<~SQL)
            INSERT INTO stock_movements (
              purchase_order_id,
              receipt_id,
              purchase_order_line_id,
              product_id,
              quantity
            )
            SELECT
              receipt_line.purchase_order_id,
              receipt_line.receipt_id,
              receipt_line.purchase_order_line_id,
              order_line.product_id,
              receipt_line.received_quantity
            FROM goods_receipt_lines AS receipt_line
            JOIN purchase_order_lines AS order_line
              ON order_line.purchase_order_id =
                 receipt_line.purchase_order_id
              AND order_line.id =
                  receipt_line.purchase_order_line_id
            WHERE NOT EXISTS (
              SELECT 1
              FROM stock_movements AS movement
              WHERE movement.purchase_order_id =
                    receipt_line.purchase_order_id
                AND movement.receipt_id =
                    receipt_line.receipt_id
                AND movement.purchase_order_line_id =
                    receipt_line.purchase_order_line_id
            )
          SQL

          inserted_count = @database.changes

          verify_consistency!
        end

        inserted_count
      end

      private

      def verify_consistency!
        unless @database.execute("PRAGMA foreign_key_check").empty?
          raise "Inventory upgrade failed: foreign key violations exist"
        end

        mismatches = @database.get_first_value(<<~SQL)
          SELECT COUNT(*)
          FROM goods_receipt_lines AS receipt_line
          JOIN purchase_order_lines AS order_line
            ON order_line.purchase_order_id =
               receipt_line.purchase_order_id
            AND order_line.id =
                receipt_line.purchase_order_line_id
          LEFT JOIN stock_movements AS movement
            ON movement.purchase_order_id =
               receipt_line.purchase_order_id
            AND movement.receipt_id =
                receipt_line.receipt_id
            AND movement.purchase_order_line_id =
                receipt_line.purchase_order_line_id
          WHERE movement.purchase_order_id IS NULL
             OR movement.product_id <> order_line.product_id
             OR movement.quantity <> receipt_line.received_quantity
        SQL

        return if mismatches.zero?

        raise "Inventory upgrade failed: movements disagree with receipts"
      end
    end
  end
end
