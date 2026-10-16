# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/procurement/persistence/sqlite_product_repository"

class SQLiteProductRepositoryTest < Minitest::Test
  def setup
    @database = SQLite3::Database.new(":memory:")
    @database.results_as_hash = true
    @database.execute("PRAGMA foreign_keys = ON")

    schema_path = File.join(__dir__, "..", "db", "schema.sql")
    @database.execute_batch(File.read(schema_path))

    @repository =
      Procurement::Persistence::SQLiteProductRepository.new(@database)
  end

  def teardown
    @database&.close
  end

  def test_loads_a_saved_product_as_a_new_object
    original = build_product

    @repository.add(original)
    loaded = @repository.find(original.id)

    assert_instance_of Procurement::Product, loaded
    refute_same original, loaded
    assert_equal original.id, loaded.id
    assert_equal original.sku, loaded.sku
    assert_equal original.name, loaded.name
  end

  def test_returns_nil_for_an_unknown_id
    assert_nil @repository.find("missing-product")
  end

  def test_rejects_duplicate_ids_without_replacing_the_original
    @repository.add(build_product)

    assert_raises(SQLite3::ConstraintException) do
      @repository.add(build_product(sku: "OTHER-001"))
    end

    assert_equal "KEY-001", @repository.find("product-001").sku
  end

  def test_rejects_duplicate_skus
    @repository.add(build_product)

    assert_raises(SQLite3::ConstraintException) do
      @repository.add(build_product(id: "product-002"))
    end

    assert_nil @repository.find("product-002")
  end

  def test_preserves_names_containing_apostrophes
    @repository.add(build_product(name: "Operator's keyboard"))

    assert_equal "Operator's keyboard",
                 @repository.find("product-001").name
  end

  private

  def build_product(**overrides)
    attributes = {
      id: "product-001",
      sku: "KEY-001",
      name: "USB keyboard"
    }

    Procurement::Product.new(**attributes.merge(overrides))
  end
end
