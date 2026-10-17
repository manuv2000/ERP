# frozen_string_literal: true

require "minitest/autorun"
require "rack/mock"
require "stringio"
require_relative "../lib/procurement/api/http_app"

class HttpAppTest < Minitest::Test
  def setup
    app = Procurement::API::HttpApp.new(
      database_path: ":memory:",
      logger: Logger.new(StringIO.new)
    )

    @request = Rack::MockRequest.new(app)
  end

  def test_rejects_get_requests
    response = @request.get("/graphql")

    assert_equal 405, response.status
    assert_equal "POST", response["allow"]
  end

  def test_rejects_malformed_json
    response = post_json("{")

    assert_equal 400, response.status
  end

  def test_rejects_variables_that_are_not_an_object
    response = post_json(
      JSON.generate(
        query: "{ __typename }",
        variables: ["invalid"]
      )
    )

    assert_equal 400, response.status
  end

  def test_rejects_unsupported_content_type
    response = @request.post(
      "/graphql",
      "CONTENT_TYPE" => "text/plain",
      input: "{ __typename }"
    )

    assert_equal 415, response.status
  end

  def test_executes_a_graphql_request
    response = post_json(
      JSON.generate(query: "{ __typename }")
    )

    assert_equal 200, response.status
    assert_equal(
      { "data" => { "__typename" => "Query" } },
      JSON.parse(response.body)
    )
  end

  private

  def post_json(body)
    @request.post(
      "/graphql",
      "CONTENT_TYPE" => "application/json",
      input: body
    )
  end
end
