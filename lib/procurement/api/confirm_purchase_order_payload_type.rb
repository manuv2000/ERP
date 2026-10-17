# frozen_string_literal: true

require_relative "purchase_order_type"

module Procurement
  module API
    class ConfirmPurchaseOrderPayloadType < GraphQL::Schema::Object
      graphql_name "ConfirmPurchaseOrderPayload"

      field :order, PurchaseOrderType, null: true
      field :errors, [String], null: false
    end
  end
end
