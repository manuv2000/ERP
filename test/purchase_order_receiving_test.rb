# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/procurement'

class PurchaseOrderReceivingTest < Minitest::Test
  def test_records_a_partial_delivery
    order = build_order

    order.record_receipt(build_receipt(quantity: 6))

    assert_equal 6, order.received_quantity_for('line-001')
    assert_equal 4, order.outstanding_quantity_for('line-001')
    assert_equal :confirmed, order.status
  end

  def test_accumulates_separate_deliveries
    order = build_order

    order.record_receipt(build_receipt(quantity: 6))
    order.record_receipt(build_receipt(id: 'receipt-002', quantity: 4))

    assert_equal 10, order.received_quantity_for('line-001')
    assert_equal 0, order.outstanding_quantity_for('line-001')
  end

  def test_rejects_over_delivery_without_changing_received_quantity
    order = build_order
    order.record_receipt(build_receipt(quantity: 6))

    assert_raises(ArgumentError) do
      order.record_receipt(build_receipt(id: 'receipt-002', quantity: 5))
    end

    assert_equal 6, order.received_quantity_for('line-001')
    assert_equal 1, order.receipts.size
  end

  def test_rejects_the_same_receipt_twice
    order = build_order
    receipt = build_receipt(quantity: 3)
    order.record_receipt(receipt)

    assert_raises(ArgumentError) do
      order.record_receipt(receipt)
    end

    assert_equal 3, order.received_quantity_for('line-001')
  end

  def test_rejects_a_receipt_for_another_order
    order = build_order

    assert_raises(ArgumentError) do
      order.record_receipt(
        build_receipt(purchase_order_id: 'order-002')
      )
    end

    assert_equal [], order.receipts
  end

  def test_rejects_receiving_against_a_draft
    order = build_order(confirmed: false)

    assert_raises(Procurement::PurchaseOrder::InvalidStateError) do
      order.record_receipt(build_receipt)
    end
  end

  def test_rejects_the_entire_receipt_if_one_line_is_unknown
    order = build_order

    receipt = Procurement::GoodsReceipt.new(
      id: 'receipt-001',
      purchase_order_id: order.id,
      lines: [
        build_receipt_line(quantity: 3),
        build_receipt_line(order_line_id: 'unknown-line', quantity: 1)
      ]
    )

    assert_raises(ArgumentError) do
      order.record_receipt(receipt)
    end

    assert_equal 0, order.received_quantity_for('line-001')
    assert_equal [], order.receipts
  end

  def test_rejects_duplicate_order_lines_within_a_receipt
    assert_raises(ArgumentError) do
      Procurement::GoodsReceipt.new(
        id: 'receipt-001',
        purchase_order_id: 'order-001',
        lines: [
          build_receipt_line(quantity: 6),
          build_receipt_line(quantity: 6)
        ]
      )
    end
  end

  def test_rejects_an_empty_receipt
    assert_raises(ArgumentError) do
      Procurement::GoodsReceipt.new(
        id: 'receipt-001',
        purchase_order_id: 'order-001',
        lines: []
      )
    end
  end

  def test_rejects_invalid_received_quantities
    [0, -1, 1.5, '6', nil].each do |quantity|
      assert_raises(ArgumentError) do
        build_receipt_line(quantity: quantity)
      end
    end
  end

  private

  def build_order(confirmed: true)
    order = Procurement::PurchaseOrder.new(
      id: 'order-001',
      supplier_id: 'supplier-001'
    )

    order.add_line(
      Procurement::PurchaseOrderLine.new(
        id: 'line-001',
        product_id: 'product-001',
        ordered_quantity: 10
      )
    )

    order.confirm! if confirmed
    order
  end

  def build_receipt(
    id: 'receipt-001',
    quantity: 6,
    purchase_order_id: 'order-001'
  )
    Procurement::GoodsReceipt.new(
      id: id,
      purchase_order_id: purchase_order_id,
      lines: [build_receipt_line(quantity: quantity)]
    )
  end

  def build_receipt_line(order_line_id: 'line-001', quantity: 6)
    Procurement::GoodsReceiptLine.new(
      purchase_order_line_id: order_line_id,
      received_quantity: quantity
    )
  end
end
