# frozen_string_literal: true

require_relative 'lib/procurement'

product = Procurement::Product.new(
  id: 'product-001',
  sku: 'KEY-001',
  name: 'USB keyboard'
)

line = Procurement::PurchaseOrderLine.new(
  id: 'line-001',
  product_id: product.id,
  ordered_quantity: 10
)

puts "Product: #{product.sku} — #{product.name}"
puts "Order line: #{line.id}"
puts "Quantity ordered: #{line.ordered_quantity}"

order = Procurement::PurchaseOrder.new(
  id: 'order-001',
  supplier_id: 'supplier-001'
)

order.add_line(line)

puts "Before confirmation: #{order.status}"

order.confirm!

puts "After confirmation: #{order.status}"
puts "Number of lines: #{order.lines.size}"

receipt_line = Procurement::GoodsReceiptLine.new(
  purchase_order_line_id: line.id,
  received_quantity: 6
)

receipt = Procurement::GoodsReceipt.new(
  id: 'receipt-001',
  purchase_order_id: order.id,
  lines: [receipt_line]
)

order.record_receipt(receipt)

puts "Ordered: #{line.ordered_quantity}"
puts "Received: #{order.received_quantity_for(line.id)}"
puts "Outstanding: #{order.outstanding_quantity_for(line.id)}"
