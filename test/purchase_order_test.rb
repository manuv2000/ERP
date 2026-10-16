# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/procurement'

class PurchaseOrderTest < Minitest::Test
  def test_starts_as_an_empty_draft
    order = build_order

    assert_equal :draft, order.status
    assert_equal [], order.lines
  end

  def test_adds_a_line_to_a_draft
    order = build_order
    line = build_line

    order.add_line(line)

    assert_equal [line], order.lines
  end

  def test_rejects_duplicate_line_ids
    order = build_order
    order.add_line(build_line)

    assert_raises(ArgumentError) do
      order.add_line(build_line(product_id: 'product-002'))
    end

    assert_equal 1, order.lines.size
  end

  def test_rejects_duplicate_products
    order = build_order
    order.add_line(build_line)

    assert_raises(ArgumentError) do
      order.add_line(build_line(id: 'line-002'))
    end

    assert_equal 1, order.lines.size
  end

  def test_rejects_objects_that_are_not_order_lines
    order = build_order

    assert_raises(ArgumentError) do
      order.add_line('not a line')
    end

    assert_equal [], order.lines
  end

  def test_confirms_an_order_with_a_line
    order = build_order
    order.add_line(build_line)

    order.confirm!

    assert_equal :confirmed, order.status
  end

  def test_cannot_confirm_an_empty_order
    order = build_order

    assert_raises(Procurement::PurchaseOrder::InvalidStateError) do
      order.confirm!
    end

    assert_equal :draft, order.status
  end

  def test_cannot_add_lines_after_confirmation
    order = build_order
    order.add_line(build_line)
    order.confirm!

    assert_raises(Procurement::PurchaseOrder::InvalidStateError) do
      order.add_line(
        build_line(id: 'line-002', product_id: 'product-002')
      )
    end

    assert_equal 1, order.lines.size
  end

  def test_cannot_confirm_twice
    order = build_order
    order.add_line(build_line)
    order.confirm!

    assert_raises(Procurement::PurchaseOrder::InvalidStateError) do
      order.confirm!
    end
  end

  def test_callers_cannot_modify_the_lines_array
    order = build_order
    order.add_line(build_line)

    assert_raises(FrozenError) do
      order.lines.clear
    end

    assert_equal 1, order.lines.size
  end

  def test_keeps_multiple_distinct_lines_in_insertion_order
    order = build_order

    first_line = build_line
    second_line = build_line(
      id: 'line-002',
      product_id: 'product-002'
    )

    order.add_line(first_line)
    order.add_line(second_line)

    assert_equal [first_line, second_line], order.lines
  end

  private

  def build_order
    Procurement::PurchaseOrder.new(
      id: 'order-001',
      supplier_id: 'supplier-001'
    )
  end

  def build_line(**overrides)
    attributes = {
      id: 'line-001',
      product_id: 'product-001',
      ordered_quantity: 10
    }

    Procurement::PurchaseOrderLine.new(**attributes.merge(overrides))
  end
end
