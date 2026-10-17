# frozen_string_literal: true

require_relative "query_type"
require_relative "mutation_type"

module Procurement
  module API
    class Schema < GraphQL::Schema
      query QueryType
      mutation MutationType
    end
  end
end
