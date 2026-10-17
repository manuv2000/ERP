# frozen_string_literal: true

require "graphql"

module Procurement
  module API
    class GoodsReceiptLineInput < GraphQL::Schema::InputObject
      graphql_name "GoodsReceiptLineInput"

      argument :purchase_order_line_id, ID, required: true
      argument :received_quantity, Integer, required: true
    end
  end
end
