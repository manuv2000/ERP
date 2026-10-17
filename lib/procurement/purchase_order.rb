# frozen_string_literal: true
require_relative "errors"

module Procurement
  class PurchaseOrder
    class InvalidStateError < StandardError; end

    attr_reader :id, :supplier_id, :status

    def initialize(id:, supplier_id:)
      @id = validated_text(id, :id)
      @supplier_id = validated_text(supplier_id, :supplier_id)
      @status = :draft
      @lines_by_id = {}
      @receipts = []
    end

    def lines
      @lines_by_id.values.freeze
    end

    def add_line(line)
      ensure_draft!

      raise ValidationError, 'line must be a PurchaseOrderLine' unless line.is_a?(PurchaseOrderLine)

      raise ValidationError, 'line id already exists in this order' if @lines_by_id.key?(line.id)

      duplicate_product = @lines_by_id.each_value.any? do |existing|
        existing.product_id == line.product_id
      end

      if duplicate_product
        raise ValidationError, 'product already exists in this order'
      end

      @lines_by_id[line.id] = line
      self
    end

    def confirm!
      ensure_draft!

      raise InvalidStateError, 'cannot confirm an empty order' if @lines_by_id.empty?

      @status = :confirmed
      self
    end

    def receipts
      @receipts.dup.freeze
    end

    def received_quantity_for(order_line_id)
      find_line!(order_line_id)

      @receipts.sum do |receipt|
        receipt.lines.sum do |receipt_line|
          if receipt_line.purchase_order_line_id == order_line_id
            receipt_line.received_quantity
          else
            0
          end
        end
      end
    end

    def outstanding_quantity_for(order_line_id)
      line = find_line!(order_line_id)

      line.ordered_quantity - received_quantity_for(order_line_id)
    end

    def record_receipt(receipt)
      raise InvalidStateError, 'order must be confirmed to receive goods' unless @status == :confirmed

      raise ValidationError, 'receipt must be a GoodsReceipt' unless receipt.is_a?(GoodsReceipt)

      raise ValidationError, 'receipt belongs to a different order' unless receipt.purchase_order_id == @id

      if @receipts.any? { |existing| existing.id == receipt.id }
        raise ValidationError, 'receipt has already been recorded'
      end

      receipt.lines.each do |receipt_line|
        outstanding = outstanding_quantity_for(
          receipt_line.purchase_order_line_id
        )

        if receipt_line.received_quantity > outstanding
          raise ValidationError, 'received quantity exceeds outstanding quantity'
        end
      end

      @receipts << receipt
      self
    end

    private

    def find_line!(order_line_id)
      @lines_by_id.fetch(order_line_id) do
        raise ValidationError, 'order line does not exist'
      end
    end

    def ensure_draft!
      return if @status == :draft

      raise InvalidStateError, 'order must be a draft'
    end

    def validated_text(value, field)
      raise ValidationError, "#{field} must be a String" unless value.is_a?(String)

      normalized = value.strip

      raise ValidationError, "#{field} must not be blank" if normalized.empty?

      normalized.freeze
    end
  end
end
