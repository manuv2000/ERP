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