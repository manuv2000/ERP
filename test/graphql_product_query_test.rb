# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/api/schema"
require_relative "../lib/procurement/persistence/sqlite_product_repository"

class GraphQLProductQueryTest < Minitest::Test
  QUERY = <<~GRAPHQL
    query FindProduct($id: ID!) {
      product(id: $id) {
        id
        sku
        name
      }
    }
  GRAPHQL

  def setup
    @database = SQLite3::Database.new(":memory:")
    @database.results_as_hash = true
    @database.execute("PRAGMA foreign_keys = ON")

    schema_path = File.join(__dir__, "..", "db", "schema.sql")
    @database.execute_batch(File.read(schema_path))

    @products =
      Procurement::Persistence::SQLiteProductRepository.new(@database)

    @products.add(
      Procurement::Product.new(
        id: "product-001",
        sku: "KEY-001",
        name: "USB keyboard"
      )
    )
  end

  def teardown
    @database&.close
  end

  def test_returns_a_stored_product
    result = execute_query(QUERY, variables: { "id" => "product-001" })

    refute result.key?("errors"), result["errors"].inspect

    assert_equal(
      {
        "id" => "product-001",
        "sku" => "KEY-001",
        "name" => "USB keyboard"
      },
      result.fetch("data").fetch("product")
    )
  end

  def test_returns_null_for_a_missing_product
    result = execute_query(QUERY, variables: { "id" => "missing-product" })

    refute result.key?("errors"), result["errors"].inspect
    assert_nil result.fetch("data").fetch("product")
  end

  def test_returns_only_requested_fields
    query = <<~GRAPHQL
      {
        product(id: "product-001") {
          name
        }
      }
    GRAPHQL

    result = execute_query(query)

    refute result.key?("errors"), result["errors"].inspect

    assert_equal(
      { "name" => "USB keyboard" },
      result.fetch("data").fetch("product")
    )
  end

  def test_rejects_a_missing_required_variable
    result = execute_query(QUERY)

    refute_empty result.fetch("errors")
    assert_nil result["data"]
  end

  def test_rejects_a_field_outside_the_schema
    query = <<~GRAPHQL
      {
        product(id: "product-001") {
          unknownField
        }
      }
    GRAPHQL

    result = execute_query(query)

    refute_empty result.fetch("errors")
    assert_nil result["data"]
  end

  private

  def execute_query(query, variables: {})
    Procurement::API::Schema.execute(
      query,
      variables: variables,
      context: { products: @products }
    ).to_h
  end
end
