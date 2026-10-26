# frozen_string_literal: true

require_relative "../../procurement"

module Procurement
  module Application
    class ReceiveGoods
      def initialize(orders:, stock_movements:, transaction:)
        @orders = orders
        @stock_movements = stock_movements
        @transaction = transaction
      end

      def call(order_id:, receipt:)
        order = nil

        @transaction.call do
          order = @orders.find(order_id)

          raise OrderNotFoundError, "order does not exist" unless order

          validate_receipt_reference!(order, receipt)

          existing_receipt = order.receipts.find do |stored_receipt|
            stored_receipt.id == receipt.id
          end

          if existing_receipt
            unless existing_receipt.same_contents_as?(receipt)
              raise ReceiptConflictError,
                    "receipt id already exists with different contents"
            end

            next
          end

          order.record_receipt(receipt)
          @orders.insert_receipt(receipt)
          record_stock_movements(order, receipt)
        end

        order
      end

      private

      def validate_receipt_reference!(order, receipt)
        unless receipt.is_a?(GoodsReceipt)
          raise ValidationError, "receipt must be a GoodsReceipt"
        end

        unless receipt.purchase_order_id == order.id
          raise ValidationError, "receipt belongs to a different order"
        end
      end

      def record_stock_movements(order, receipt)
        order_lines_by_id = order.lines.to_h do |line|
          [line.id, line]
        end

        receipt.lines.each do |receipt_line|
          order_line = order_lines_by_id.fetch(
            receipt_line.purchase_order_line_id
          )

          @stock_movements.add(
            StockMovement.new(
              product_id: order_line.product_id,
              quantity: receipt_line.received_quantity,
              purchase_order_id: order.id,
              receipt_id: receipt.id,
              purchase_order_line_id: order_line.id
            )
          )
        end
      end
    end
  end
end
