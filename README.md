# Procurement

A Ruby purchasing application developed incrementally to explore
business rules, persistence, and replaceable enterprise integrations.

## Current functionality

- Products with validated identifiers and names.
- Purchase orders containing unique product lines.
- Draft-to-confirmed order transition.
- Partial goods receipts.
- Prevention of over-delivery and duplicate receipt recording.
- Calculation of received and outstanding quantities.

## Current scope

Quantities are positive whole numbers.
One goods receipt belongs to one purchase order.

Supplier and product existence checks, persistent storage, stock
movements, and external integrations are not implemented yet.

## Requirements

- Ruby 3.4.11
- Bundler

## Setup

    bundle install

## Run the demonstration

    bundle exec ruby demo.rb

## Run all tests

    bundle exec ruby -Itest test/all_test.rb

## Design decisions

Purchase order lines are stored internally in a hash keyed by line ID.
The public interface exposes a frozen array of those lines.

Receipts are immutable records. Received quantities are calculated
from recorded receipts.

All receipt lines are validated before the receipt is added to an order.

The application uses SQLite with explicit Ruby repositories. Products,
purchase orders, order lines, and partial goods receipts are stored in
five related tables. Orders and their lines are inserted atomically;
receipt recording reloads the saved order and validates quantities inside
a write transaction. Received and outstanding quantities are calculated
from receipt records.

This baseline supports insertion and retrieval, plus adding receipts to
stored confirmed orders. Updating a stored draft to confirmed, supplier
storage, stock movements, migrations, and GraphQL are still planned.

Stored draft orders can be confirmed through a dedicated transactional operation. Editing stored order lines and cancellation are not implemented yet.

See [Database design and persistence](docs/database-design.md) for the
schema, constraints, operation sequences, and current limitations.

Run all tests with `bundle exec ruby -Itest test/all_tests.rb`.

## GraphQL API

The GraphQL schema currently executes directly from Ruby, without an
HTTP server.

Supported operations:

- Query a product by ID.
- Query a purchase order with its lines and receiving quantities.
- Confirm a stored draft order.
- Record a goods receipt containing one or more lines.

Mutations return the updated order and an empty `errors` list on success.
Expected business rejections return a null order and error messages.
Unexpected exceptions are not converted into business-error payloads.

Run the query demonstrations:

    bundle exec ruby graphql_demo.rb product-001
    bundle exec ruby graphql_order_demo.rb ORDER_ID

Order reconstruction uses a read transaction, or reuses the transaction
of the operation calling it. Separate root lookups do not share a
request-wide database snapshot.

## Local GraphQL API

The application exposes a GraphQL endpoint at:

http://127.0.0.1:9292/graphql

Initialize the demonstration database before the first use:

```bash
bundle exec ruby cli.rb init
```

Start the local server:

```bash
bundle exec puma -b tcp://127.0.0.1:9292 config.ru
```

Keep that terminal open. Send requests from another terminal:

```bash
curl -sS http://127.0.0.1:9292/graphql \
  -H 'Content-Type: application/json' \
  --data-binary '{"query":"{ product(id: \"product-001\") { id sku name } }'
```

The endpoint accepts POST requests containing a JSON GraphQL request.
There is currently no homepage or browser-based query editor.

Supported operations include product and purchase-order queries,
purchase-order confirmation, and recording goods receipts.

Business rejections are returned in mutation payloads through the
`errors` field. Clients must inspect the response body even when
the HTTP status is 200.

The HTTP application opens a database connection for each request.
The CLI and API share the same SQLite database.

### Tests

```bash
bundle exec ruby -Itest test/all_tests.rb
```

The HTTP receipt integration test uses an isolated temporary SQLite
database. It verifies successful receipt persistence and rejection
of a repeated receipt without changing saved quantities.

### Current scope

This is a local development application without authentication.
Goods receipts track deliveries against purchase orders; warehouse
stock movements and accounting integration are not implemented yet.
