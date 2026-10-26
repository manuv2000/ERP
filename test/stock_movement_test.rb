require "minitest/autorun"
require_relative "../lib/procurement"

class StockMovementTest < Minitest::Test
  def test_preserves_quantity_and_source_references
    movement = build_movement

    assert_equal "product-001", movement.product_id
    assert_equal 6, movement.quantity
    assert_equal "order-001", movement.purchase_order_id
    assert_equal "receipt-001", movement.receipt_id
    assert_equal "line-001", movement.purchase_order_line_id
  end

  def test_normalizes_identifiers_without_modifying_the_input
    original = String.new(" product-001 ")
    movement = build_movement(product_id: original)

    assert_equal "product-001", movement.product_id
    assert_equal " product-001 ", original

    original.replace("different-product")

    assert_equal "product-001", movement.product_id
  end

  def test_rejects_invalid_identifiers
    attributes = [
      :product_id,
      :purchase_order_id,
      :receipt_id,
      :purchase_order_line_id
    ]

    attributes.each do |attribute|
      [nil, "", "   ", 123].each do |invalid_value|
        assert_raises(Procurement::ValidationError) do
          build_movement(**{ attribute => invalid_value })
        end
      end
    end
  end

  def test_rejects_non_positive_or_non_integer_quantities
    [0, -1, 1.5, "6", nil].each do |invalid_quantity|
      assert_raises(Procurement::ValidationError) do
        build_movement(quantity: invalid_quantity)
      end
    end
  end

  def test_cannot_be_modified_after_creation
    movement = build_movement

    assert_raises(FrozenError) do
      movement.product_id.replace("different-product")
    end

    assert_raises(FrozenError) do
      movement.instance_variable_set(:@quantity, 100)
    end
  end

  private

  def build_movement(**overrides)
    attributes = {
      product_id: "product-001",
      quantity: 6,
      purchase_order_id: "order-001",
      receipt_id: "receipt-001",
      purchase_order_line_id: "line-001"
    }

    Procurement::StockMovement.new(**attributes.merge(overrides))
  end
end
