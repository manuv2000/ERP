# frozen_string_literal: true

require "graphql"

module Procurement
  module API
    class ProductType < GraphQL::Schema::Object
      graphql_name "Product"

      field :id, ID, null: false
      field :sku, String, null: false
      field :name, String, null: false
    end
  end
end
