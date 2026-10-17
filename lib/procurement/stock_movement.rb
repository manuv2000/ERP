require_relative "errors"

module Procurement
  class StockMovement
    attr_reader :product_id,
                :quantity,
                :purchase_order_id,
                :receipt_id,
                :purchase_order_line_id

    def initialize(
      product_id:,
      quantity:,
      purchase_order_id:,
      receipt_id:,
      purchase_order_line_id:
    )
      @product_id = validate_identifier(product_id, "product_id")
      @purchase_order_id =
        validate_identifier(purchase_order_id, "purchase_order_id")
      @receipt_id = validate_identifier(receipt_id, "receipt_id")
      @purchase_order_line_id =
        validate_identifier(purchase_order_line_id, "purchase_order_line_id")

      unless quantity.is_a?(Integer) && quantity.positive?
        raise ValidationError, "quantity must be a positive Integer"
      end

      @quantity = quantity

      freeze
    end

    private

    def validate_identifier(value, name)
      unless value.is_a?(String) && !value.strip.empty?
        raise ValidationError, "#{name} must be a non-empty String"
      end

      value.strip.freeze
    end
  end
end
