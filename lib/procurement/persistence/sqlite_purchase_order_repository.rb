# frozen_string_literal: true

require "sqlite3"
require_relative "../../procurement"

module Procurement
  module Persistence
    class SQLitePurchaseOrderRepository
      def initialize(database)
        @database = database
      end

      def add(order)
        unless order.is_a?(PurchaseOrder)
          raise ArgumentError, "order must be a PurchaseOrder"
        end

        unless order.receipts.empty?
          raise ArgumentError, "receipt persistence is not implemented yet"
        end

        @database.transaction do
          @database.execute(
            "INSERT INTO purchase_orders (id, supplier_id, status)
             VALUES (?, ?, ?)",
            [order.id, order.supplier_id, order.status.to_s]
          )

          order.lines.each_with_index do |line, position|
            @database.execute(
              "INSERT INTO purchase_order_lines
                 (purchase_order_id, id, product_id,
                  ordered_quantity, position)
               VALUES (?, ?, ?, ?, ?)",
              [
                order.id,
                line.id,
                line.product_id,
                line.ordered_quantity,
                position
              ]
            )
          end
        end

        order
      end

      def find(id)
        row = @database.get_first_row(
          "SELECT id, supplier_id, status
           FROM purchase_orders WHERE id = ?",
          [id]
        )

        return nil unless row

        order = PurchaseOrder.new(
          id: row.fetch("id"),
          supplier_id: row.fetch("supplier_id")
        )

        line_rows = @database.execute(
          "SELECT id, product_id, ordered_quantity
           FROM purchase_order_lines
           WHERE purchase_order_id = ?
           ORDER BY position",
          [id]
        )

        line_rows.each do |line_row|
          order.add_line(
            PurchaseOrderLine.new(
              id: line_row.fetch("id"),
              product_id: line_row.fetch("product_id"),
              ordered_quantity: line_row.fetch("ordered_quantity")
            )
          )
        end

        case row.fetch("status")
        when "confirmed"
          order.confirm!
        when "draft"
          # The constructor already created a draft.
        else
          raise ArgumentError, "unsupported stored order status"
        end
        load_receipts_into(order)
        order
      end

      def record_receipt(order_id, receipt)
        updated_order = nil

        @database.transaction(:immediate) do
          updated_order = find(order_id)

          unless updated_order
            raise ArgumentError, "order does not exist"
          end

          updated_order.record_receipt(receipt)

          @database.execute(
            "INSERT INTO goods_receipts (purchase_order_id, id)
            VALUES (?, ?)",
            [updated_order.id, receipt.id]
          )

          receipt.lines.each_with_index do |line, position|
            @database.execute(
              "INSERT INTO goods_receipt_lines
                (purchase_order_id, receipt_id, purchase_order_line_id,
                  received_quantity, position)
              VALUES (?, ?, ?, ?, ?)",
              [
                updated_order.id,
                receipt.id,
                line.purchase_order_line_id,
                line.received_quantity,
                position
              ]
            )
          end
        end

        updated_order
      end
      
      def confirm(order_id)
        order = nil

        @database.transaction(:immediate) do
          order = find(order_id)

          raise ArgumentError, "order does not exist" unless order

          order.confirm!

          @database.execute(
            "UPDATE purchase_orders SET status = ? WHERE id = ?",
            [order.status.to_s, order.id]
          )
        end

        order
      end
      
      private

      def load_receipts_into(order)
        receipt_rows = @database.execute(
          "SELECT id
          FROM goods_receipts
          WHERE purchase_order_id = ?
          ORDER BY id",
          [order.id]
        )

        receipt_rows.each do |receipt_row|
          line_rows = @database.execute(
            "SELECT purchase_order_line_id, received_quantity
            FROM goods_receipt_lines
            WHERE purchase_order_id = ? AND receipt_id = ?
            ORDER BY position",
            [order.id, receipt_row.fetch("id")]
          )

          lines = line_rows.map do |line_row|
            GoodsReceiptLine.new(
              purchase_order_line_id: line_row.fetch("purchase_order_line_id"),
              received_quantity: line_row.fetch("received_quantity")
            )
          end

          receipt = GoodsReceipt.new(
            id: receipt_row.fetch("id"),
            purchase_order_id: order.id,
            lines: lines
          )

          order.record_receipt(receipt)
        end
      end
    end
  end
end
