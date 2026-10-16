# frozen_string_literal: true

module Procurement
  class Product
    attr_reader :id, :sku, :name

    def initialize(id:, sku:, name:)
      @id = validated_text(id, :id)
      @sku = validated_text(sku, :sku)
      @name = validated_text(name, :name)
    end

    private

    def validated_text(value, field)
      raise ArgumentError, "#{field} must be a String" unless value.is_a?(String)

      normalized = value.strip

      raise ArgumentError, "#{field} must not be blank" if normalized.empty?

      normalized.freeze
    end
  end
end
