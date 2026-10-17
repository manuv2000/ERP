# frozen_string_literal: true

require_relative "goods_receipt_line_input"

module Procurement
  module API
    class RecordGoodsReceiptInput < GraphQL::Schema::InputObject
      graphql_name "RecordGoodsReceiptInput"

      argument :purchase_order_id, ID, required: true
      argument :receipt_id, ID, required: true
      argument :lines, [GoodsReceiptLineInput], required: true
    end
  end
end
