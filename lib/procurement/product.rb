# frozen_string_literal: true

module Procurement
  class Product
    attr_reader :id, :sku, :name

    def initialize(id:, sku:, name:)
      @id = validated_text(id, :id)
      @sku = validated_text(sku, :sku)
      @name = validated_text(name, :name)
    end

    def test_rolls_back_receipt_when_a_line_insert_fails
      order = build_order
      order.confirm!
      @orders.add(order)

      @database.execute_batch(<<~SQL)
        CREATE TEMP TRIGGER reject_receipt_line
        BEFORE INSERT ON goods_receipt_lines
        BEGIN
          SELECT RAISE(ABORT, 'simulated write failure');
        END;
      SQL

      assert_raises(SQLite3::ConstraintException) do
        @orders.record_receipt(
          order.id,
          build_receipt(id: "receipt-001", quantity: 6)
        )
      end

      loaded = @orders.find(order.id)

      assert_equal [], loaded.receipts
      assert_equal 0, loaded.received_quantity_for("line-001")
    end

    private

    def build_receipt(id:, quantity:)
      Procurement::GoodsReceipt.new(
        id: id,
        purchase_order_id: "order-001",
        lines: [
          Procurement::GoodsReceiptLine.new(
            purchase_order_line_id: "line-001",
            received_quantity: quantity
          )
        ]
      )
    end

    def validated_text(value, field)
      raise ArgumentError, "#{field} must be a String" unless value.is_a?(String)

      normalized = value.strip

      raise ArgumentError, "#{field} must not be blank" if normalized.empty?

      normalized.freeze
    end
  end
end
