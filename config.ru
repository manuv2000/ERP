# frozen_string_literal: true

require_relative "lib/procurement/api/http_app"

database_path = File.join(__dir__, "db", "procurement.sqlite3")

run Procurement::API::HttpApp.new(database_path: database_path)
