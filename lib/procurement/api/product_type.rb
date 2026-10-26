# frozen_string_literal: true

require "graphql"

module Procurement
  module API
    class ProductType < GraphQL::Schema::Object
      graphql_name "Product"

      field :id, ID, null: false
      field :sku, String, null: false
      field :name, String, null: false
      field :quantity_on_hand, Integer, null: false

      def quantity_on_hand
        context.fetch(:stock_movements).quantity_on_hand(object.id)
      end
    end
  end
end
