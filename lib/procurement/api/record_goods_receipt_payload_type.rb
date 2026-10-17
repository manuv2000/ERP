# frozen_string_literal: true

require_relative "purchase_order_type"

module Procurement
  module API
    class RecordGoodsReceiptPayloadType < GraphQL::Schema::Object
      graphql_name "RecordGoodsReceiptPayload"

      field :order, PurchaseOrderType, null: true
      field :errors, [String], null: false
    end
  end
end
