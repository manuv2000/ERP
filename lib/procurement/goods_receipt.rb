# frozen_string_literal: true

module Procurement
  class GoodsReceipt
    attr_reader :id, :purchase_order_id, :lines

    def initialize(id:, purchase_order_id:, lines:)
      @id = validated_text(id, :id)
      @purchase_order_id = validated_text(
        purchase_order_id,
        :purchase_order_id
      )

      raise ArgumentError, 'lines must be a non-empty Array' unless lines.is_a?(Array) && !lines.empty?

      unless lines.all? { |line| line.is_a?(GoodsReceiptLine) }
        raise ArgumentError, 'every line must be a GoodsReceiptLine'
      end

      order_line_ids = lines.map(&:purchase_order_line_id)

      unless order_line_ids.uniq.size == order_line_ids.size
        raise ArgumentError, 'an order line cannot repeat within a receipt'
      end

      @lines = lines.dup.freeze

      freeze
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
