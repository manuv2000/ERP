# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/procurement'

class PurchaseOrderLineTest < Minitest::Test
  def test_stores_valid_line_details
    line = build_line

    assert_equal 'line-001', line.id
    assert_equal 'product-001', line.product_id
    assert_equal 10, line.ordered_quantity
  end

  def test_accepts_one_unit
    line = build_line(ordered_quantity: 1)

    assert_equal 1, line.ordered_quantity
  end

  def test_rejects_zero_and_negative_quantities
    [0, -1].each do |quantity|
      assert_raises(ArgumentError) do
        build_line(ordered_quantity: quantity)
      end
    end
  end

  def test_rejects_non_integer_quantities
    [1.5, 10.0, '10', nil, true].each do |quantity|
      assert_raises(ArgumentError) do
        build_line(ordered_quantity: quantity)
      end
    end
  end

  def test_rejects_blank_product_id
    assert_raises(ArgumentError) do
      build_line(product_id: ' ')
    end
  end

  def test_rejects_blank_line_id
    assert_raises(ArgumentError) do
      build_line(id: '')
    end
  end

  private

  def build_line(**overrides)
    attributes = {
      id: 'line-001',
      product_id: 'product-001',
      ordered_quantity: 10
    }

    Procurement::PurchaseOrderLine.new(**attributes.merge(overrides))
  end
end
