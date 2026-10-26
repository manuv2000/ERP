# frozen_string_literal: true

require_relative "lib/procurement/persistence/database"
require_relative "lib/procurement/persistence/inventory_upgrade"

database_path = File.join(__dir__, "db", "procurement.sqlite3")
schema_path = File.join(__dir__, "db", "schema.sql")

unless File.file?(database_path)
  abort "Database does not exist. Run: bundle exec ruby cli.rb init"
end

Procurement::Persistence::Database.open(database_path) do |database|
  upgrade = Procurement::Persistence::InventoryUpgrade.new(
    database,
    schema_path: schema_path
  )

  count = upgrade.run

  puts "Inventory upgrade complete; created #{count} stock movements."
end
