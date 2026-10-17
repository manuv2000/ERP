# frozen_string_literal: true

require_relative "../purchase_order"
require_relative "confirm_purchase_order_payload_type"
require_relative "../errors"
require_relative "../goods_receipt"
require_relative "../goods_receipt_line"
require_relative "record_goods_receipt_input"
require_relative "record_goods_receipt_payload_type"

module Procurement
  module API
    class MutationType < GraphQL::Schema::Object
      graphql_name "Mutation"

      field :confirm_purchase_order,
            ConfirmPurchaseOrderPayloadType,
            null: false do
        argument :id, ID, required: true
      end

      field :record_goods_receipt,
            RecordGoodsReceiptPayloadType,
            null: false do
        argument :input, RecordGoodsReceiptInput, required: true
      end

      def record_goods_receipt(input:)
        lines = input.lines.map do |line|
          GoodsReceiptLine.new(
            purchase_order_line_id: line.purchase_order_line_id,
            received_quantity: line.received_quantity
          )
        end

        receipt = GoodsReceipt.new(
          id: input.receipt_id,
          purchase_order_id: input.purchase_order_id,
          lines: lines
        )

        order = context[:orders].record_receipt(
          receipt.purchase_order_id,
          receipt
        )

        { order: order, errors: [] }
      rescue ValidationError, PurchaseOrder::InvalidStateError,
            OrderNotFoundError => error
        { order: nil, errors: [error.message] }
      end

      def confirm_purchase_order(id:)
        order = context[:orders].confirm(id)

        { order: order, errors: [] }
      rescue PurchaseOrder::InvalidStateError, OrderNotFoundError => error
        { order: nil, errors: [error.message] }
      end
    end
  end
end
