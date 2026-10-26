# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement"

class GoodsReceiptComparisonTest < Minitest::Test
  def test_matches_separately_constructed_receipts
    original = build_receipt
    retry_receipt = build_receipt

    refute_same original, retry_receipt
    assert original.same_contents_as?(retry_receipt)
  end

  def test_ignores_line_order
    original = build_receipt

    reordered = build_receipt(
      quantities: [["line-002", 3], ["line-001", 6]]
    )

    assert original.same_contents_as?(reordered)
  end

  def test_detects_changed_added_or_removed_lines
    original = build_receipt

    different_contents = [
      [["line-001", 5], ["line-002", 3]],
      [["line-001", 6]],
      [["line-001", 6], ["line-002", 3], ["line-003", 1]],
      [["line-001", 6], ["line-003", 3]]
    ]

    different_contents.each do |quantities|
      other = build_receipt(quantities: quantities)

      refute original.same_contents_as?(other),
             "Expected different contents for #{quantities.inspect}"
    end
  end

  def test_detects_a_different_order
    original = build_receipt
    other = build_receipt(order_id: "order-002")

    refute original.same_contents_as?(other)
  end

  def test_contents_can_match_even_with_different_receipt_ids
    original = build_receipt
    other = build_receipt(id: "receipt-002")

    assert original.same_contents_as?(other)
  end

  def test_returns_false_for_another_object_type
    refute build_receipt.same_contents_as?(nil)
  end

  private

  def build_receipt(
    id: "receipt-001",
    order_id: "order-001",
    quantities: [["line-001", 6], ["line-002", 3]]
  )
    lines = quantities.map do |line_id, quantity|
      Procurement::GoodsReceiptLine.new(
        purchase_order_line_id: line_id,
        received_quantity: quantity
      )
    end

    Procurement::GoodsReceipt.new(
      id: id,
      purchase_order_id: order_id,
      lines: lines
    )
  end
end
