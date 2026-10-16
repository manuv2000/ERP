# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/procurement'

class ProductTest < Minitest::Test
  def test_stores_valid_product_details
    product = build_product

    assert_equal 'product-001', product.id
    assert_equal 'KEY-001', product.sku
    assert_equal 'USB keyboard', product.name
  end

  def test_removes_surrounding_whitespace
    product = build_product(sku: '  KEY-001  ')

    assert_equal 'KEY-001', product.sku
  end

  def test_rejects_blank_name
    assert_raises(ArgumentError) do
      build_product(name: '   ')
    end
  end

  def test_rejects_non_string_id
    assert_raises(ArgumentError) do
      build_product(id: 123)
    end
  end

  def test_does_not_share_mutable_sku_with_caller
    original_sku = String.new('KEY-001')
    product = build_product(sku: original_sku)

    original_sku.replace('CHANGED')

    assert_equal 'KEY-001', product.sku
  end

  def test_prevents_sku_mutation_through_reader
    product = build_product

    assert_raises(FrozenError) do
      product.sku.replace('CHANGED')
    end
  end

  private

  def build_product(**overrides)
    attributes = {
      id: 'product-001',
      sku: 'KEY-001',
      name: 'USB keyboard'
    }

    Procurement::Product.new(**attributes.merge(overrides))
  end
end
