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

The application runs in memory. Quantities are positive whole numbers.
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