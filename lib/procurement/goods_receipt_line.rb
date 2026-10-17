# frozen_string_literal: true
require_relative "errors"

module Procurement
  class GoodsReceiptLine
    attr_reader :purchase_order_line_id, :received_quantity

    def initialize(purchase_order_line_id:, received_quantity:)
      raise ValidationError, 'purchase_order_line_id must be a String' unless purchase_order_line_id.is_a?(String)

      normalized_id = purchase_order_line_id.strip

      raise ValidationError, 'purchase_order_line_id must not be blank' if normalized_id.empty?

      unless received_quantity.is_a?(Integer) &&
             received_quantity.positive?
        raise ValidationError, 'received_quantity must be a positive Integer'
      end

      @purchase_order_line_id = normalized_id.freeze
      @received_quantity = received_quantity

      freeze
    end
  end
end
