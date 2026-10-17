# frozen_string_literal: true

require "graphql"

module Procurement
  module API
    class PurchaseOrderLineType < GraphQL::Schema::Object
      graphql_name "PurchaseOrderLine"

      field :id, ID, null: false
      field :product_id, ID, null: false
      field :ordered_quantity, Integer, null: false
      field :received_quantity, Integer, null: false
      field :outstanding_quantity, Integer, null: false

      def id
        line.id
      end

      def product_id
        line.product_id
      end

      def ordered_quantity
        line.ordered_quantity
      end

      def received_quantity
        order.received_quantity_for(line.id)
      end

      def outstanding_quantity
        order.outstanding_quantity_for(line.id)
      end

      private

      def line
        object.fetch(:line)
      end

      def order
        object.fetch(:order)
      end
    end
  end
end
