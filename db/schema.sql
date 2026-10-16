CREATE TABLE IF NOT EXISTS products (
  id TEXT NOT NULL PRIMARY KEY,
  sku TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS purchase_orders (
  id TEXT NOT NULL PRIMARY KEY,
  supplier_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'confirmed'))
);

CREATE TABLE IF NOT EXISTS purchase_order_lines (
  purchase_order_id TEXT NOT NULL,
  id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  ordered_quantity INTEGER NOT NULL
    CHECK (
      typeof(ordered_quantity) = 'integer'
      AND ordered_quantity > 0
    ),
  position INTEGER NOT NULL CHECK (position >= 0),

  PRIMARY KEY (purchase_order_id, id),
  UNIQUE (purchase_order_id, product_id),
  UNIQUE (purchase_order_id, position),

  FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);
CREATE TABLE IF NOT EXISTS goods_receipts (
  purchase_order_id TEXT NOT NULL,
  id TEXT NOT NULL,

  PRIMARY KEY (purchase_order_id, id),
  FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id)
);

CREATE TABLE IF NOT EXISTS goods_receipt_lines (
  purchase_order_id TEXT NOT NULL,
  receipt_id TEXT NOT NULL,
  purchase_order_line_id TEXT NOT NULL,
  received_quantity INTEGER NOT NULL
    CHECK (
      typeof(received_quantity) = 'integer'
      AND received_quantity > 0
    ),
  position INTEGER NOT NULL CHECK (position >= 0),

  PRIMARY KEY (
    purchase_order_id,
    receipt_id,
    purchase_order_line_id
  ),

  UNIQUE (purchase_order_id, receipt_id, position),

  FOREIGN KEY (purchase_order_id, receipt_id)
    REFERENCES goods_receipts(purchase_order_id, id),

  FOREIGN KEY (purchase_order_id, purchase_order_line_id)
    REFERENCES purchase_order_lines(purchase_order_id, id)
);
