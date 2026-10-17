# frozen_string_literal: true
module Procurement
  class OrderNotFoundError < StandardError
  end

  class ValidationError < ArgumentError
  end
end