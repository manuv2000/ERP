# frozen_string_literal: true

require_relative "purchase_order_line_type"

module Procurement
  module API
    class PurchaseOrderType < GraphQL::Schema::Object
      graphql_name "PurchaseOrder"

      field :id, ID, null: false
      field :supplier_id, ID, null: false
      field :status, String, null: false

      field :lines, [PurchaseOrderLineType], null: false

      def status
        object.status.to_s
      end

      def lines
        object.lines.map do |line|
          { order: object, line: line }
        end
      end
    end
  end
end
