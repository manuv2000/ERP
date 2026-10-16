# frozen_string_literal: true

module Procurement
  class PurchaseOrderLine
    attr_reader :id, :product_id, :ordered_quantity

    def initialize(id:, product_id:, ordered_quantity:)
      @id = validated_text(id, :id)
      @product_id = validated_text(product_id, :product_id)
      @ordered_quantity = validated_quantity(ordered_quantity)
    end

    private

    def validated_text(value, field)
      raise ArgumentError, "#{field} must be a String" unless value.is_a?(String)

      normalized = value.strip

      raise ArgumentError, "#{field} must not be blank" if normalized.empty?

      normalized.freeze
    end

    def validated_quantity(value)
      raise ArgumentError, 'ordered_quantity must be a positive Integer' unless value.is_a?(Integer) && value.positive?

      value
    end
  end
end
