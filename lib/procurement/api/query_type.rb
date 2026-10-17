# frozen_string_literal: true

require_relative "product_type"
require_relative "purchase_order_type"

module Procurement
  module API
    class QueryType < GraphQL::Schema::Object
      graphql_name "Query"

      field :purchase_order, PurchaseOrderType, null: true do
        argument :id, ID, required: true
      end

      field :product, ProductType, null: true do
        argument :id, ID, required: true
      end

      def product(id:)
        context[:products].find(id)
      end

      def purchase_order(id:)
        context[:orders].find(id)
      end
    end
  end
end
