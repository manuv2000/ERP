# frozen_string_literal: true

require "json"
require "logger"
require "rack"

require_relative "schema"
require_relative "../persistence/database"
require_relative "../persistence/sqlite_product_repository"
require_relative "../persistence/sqlite_purchase_order_repository"

module Procurement
  module API
    class HttpApp
      MAX_BODY_BYTES = 65_536

      def initialize(database_path:, logger: Logger.new($stderr))
        @database_path = database_path
        @logger = logger
      end

      def call(env)
        request = Rack::Request.new(env)

        unless request.path_info == "/graphql"
          return error_response(404, "Endpoint not found")
        end

        unless request.post?
          return json_response(
            405,
            { "errors" => [{ "message" => "Use POST for this endpoint" }] },
            { "allow" => "POST" }
          )
        end

        unless request.media_type == "application/json"
          return error_response(415, "Content-Type must be application/json")
        end

        body = request.body&.read(MAX_BODY_BYTES + 1) || ""

        if body.bytesize > MAX_BODY_BYTES
          return error_response(413, "Request body is too large")
        end

        payload = parse_json(body)

        unless valid_payload?(payload)
          return error_response(
            400,
            "Expected query as a non-empty String, variables as an object " \
            "or null, and operationName as a String or null"
          )
        end

        result = execute(payload)

        json_response(200, result)
      rescue SQLite3::BusyException
        error_response(503, "Database is busy; try again shortly")
      rescue StandardError => error
        @logger.error(error.full_message)

        error_response(500, "Internal server error")
      end

      private

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def valid_payload?(payload)
        return false unless payload.is_a?(Hash)

        query = payload["query"]
        variables = payload["variables"]
        operation_name = payload["operationName"]

        query.is_a?(String) &&
          !query.strip.empty? &&
          (variables.nil? || variables.is_a?(Hash)) &&
          (operation_name.nil? || operation_name.is_a?(String))
      end

      def execute(payload)
        Persistence::Database.open(@database_path) do |database|
          products = Persistence::SQLiteProductRepository.new(database)
          orders = Persistence::SQLitePurchaseOrderRepository.new(database)

          Schema.execute(
            payload.fetch("query"),
            variables: payload["variables"] || {},
            operation_name: payload["operationName"],
            context: {
              products: products,
              orders: orders
            }
          ).to_h
        end
      end

      def error_response(status, message)
        json_response(
          status,
          { "errors" => [{ "message" => message }] }
        )
      end

      def json_response(status, payload, extra_headers = {})
        headers = {
          "content-type" => "application/json",
          "cache-control" => "no-store"
        }.merge(extra_headers)

        [status, headers, [JSON.generate(payload)]]
      end
    end
  end
end
