# frozen_string_literal: true

require "sqlite3"

module Procurement
  module Persistence
    module Database
      def self.open(path)
        database = SQLite3::Database.new(path)

        begin
          database.results_as_hash = true
          database.execute("PRAGMA foreign_keys = ON")

          yield database
        ensure
          database.close
        end
      end
    end
  end
end
