defmodule Blackboex.Testing.SnippetGeneratorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Testing.SnippetGenerator

  @api %{name: "My API", slug: "my-api"}
  @request %{
    method: "POST",
    url: "http://localhost:4000/api/testuser/my-api",
    headers: [{"content-type", "application/json"}],
    body: ~s({"n": 5}),
    api_key: "test-key-123"
  }

  describe "generate/3 with :curl" do
    test "generates valid cURL command" do
      snippet = SnippetGenerator.generate(@api, :curl, @request)
      assert snippet =~ "curl"
      assert snippet =~ "POST"
      assert snippet =~ @request.url
      assert snippet =~ "Content-Type"
      assert snippet =~ "X-Api-Key"
      assert snippet =~ "test-key-123"
      assert snippet =~ ~s({"n": 5})
    end

    test "omits body flag for GET requests" do
      request = %{@request | method: "GET", body: nil}
      snippet = SnippetGenerator.generate(@api, :curl, request)
      assert snippet =~ "GET"
      refute snippet =~ "-d"
    end

    test "escapes single quotes in body to prevent shell injection" do
      request = %{@request | body: "'; rm -rf / #"}
      snippet = SnippetGenerator.generate(@api, :curl, request)
      # Shell escaping wraps in single quotes and escapes internal ones with '\''
      # The dangerous payload should be broken up by the escape sequence
      assert snippet =~ "'\\''"
    end

    test "escapes single quotes in URL" do
      request = %{@request | url: "http://localhost/api/user/slug'injection"}
      snippet = SnippetGenerator.generate(@api, :curl, request)
      # Internal single quotes must be escaped
      assert snippet =~ "'\\''"
    end
  end

  describe "generate/3 with :python" do
    test "generates valid Python requests code" do
      snippet = SnippetGenerator.generate(@api, :python, @request)
      assert snippet =~ "import requests"
      assert snippet =~ "requests.post"
      assert snippet =~ @request.url
      assert snippet =~ "Content-Type"
      assert snippet =~ "X-Api-Key"
      assert snippet =~ "test-key-123"
    end

    test "escapes single quotes in header values" do
      request = %{@request | headers: [{"x-custom", "value'with'quotes"}]}
      snippet = SnippetGenerator.generate(@api, :python, request)
      assert snippet =~ "\\'"
    end
  end

  describe "generate/3 with :javascript" do
    test "generates valid JavaScript fetch code" do
      snippet = SnippetGenerator.generate(@api, :javascript, @request)
      assert snippet =~ "fetch"
      assert snippet =~ "POST"
      assert snippet =~ @request.url
      assert snippet =~ "Content-Type"
      assert snippet =~ "X-Api-Key"
    end

    test "escapes single quotes in URL" do
      request = %{@request | url: "http://localhost/api/user/it's"}
      snippet = SnippetGenerator.generate(@api, :javascript, request)
      assert snippet =~ "\\'"
    end
  end

  describe "generate/3 with :elixir" do
    test "generates valid Elixir Req code" do
      snippet = SnippetGenerator.generate(@api, :elixir, @request)
      assert snippet =~ "Req"
      assert snippet =~ "Req.post"
      assert snippet =~ @request.url
      assert snippet =~ "x-api-key"
    end

    test "safely escapes values via inspect" do
      request = %{@request | url: ~s(http://localhost/api/user/a"b)}
      snippet = SnippetGenerator.generate(@api, :elixir, request)
      # inspect should produce escaped double quotes
      assert snippet =~ ~s(\\")
    end
  end

  describe "generate/3 with :ruby" do
    test "generates valid Ruby net/http code" do
      snippet = SnippetGenerator.generate(@api, :ruby, @request)
      assert snippet =~ "Net::HTTP"
      assert snippet =~ "URI"
      assert snippet =~ @request.url
      assert snippet =~ "X-Api-Key"
    end

    test "escapes single quotes in body" do
      request = %{@request | body: "'; system('cmd') #"}
      snippet = SnippetGenerator.generate(@api, :ruby, request)
      assert snippet =~ "\\'"
    end
  end

  describe "generate/3 with :go" do
    test "generates valid Go net/http code" do
      snippet = SnippetGenerator.generate(@api, :go, @request)
      assert snippet =~ "net/http"
      assert snippet =~ "http.NewRequest"
      assert snippet =~ @request.url
      assert snippet =~ "X-Api-Key"
    end

    test "escapes double quotes in header values" do
      request = %{@request | headers: [{"x-custom", ~s(value"break)}]}
      snippet = SnippetGenerator.generate(@api, :go, request)
      assert snippet =~ ~s(\\")
    end

    test "handles backticks in body" do
      request = %{@request | body: "body with `backtick`"}
      snippet = SnippetGenerator.generate(@api, :go, request)
      # Backticks should be escaped with concat pattern
      assert snippet =~ "\"`\""
    end
  end

  describe "generate/3 without api_key" do
    test "omits API key header when not provided" do
      request = %{@request | api_key: nil}
      snippet = SnippetGenerator.generate(@api, :curl, request)
      refute snippet =~ "X-Api-Key"
    end
  end

  describe "generate/3 without body" do
    test "omits body in Python for GET" do
      request = %{@request | method: "GET", body: nil}
      snippet = SnippetGenerator.generate(@api, :python, request)
      assert snippet =~ "requests.get"
      refute snippet =~ "json="
    end
  end

  describe "valid_language?/1" do
    test "returns true for valid languages" do
      for lang <- ~w(curl python javascript elixir ruby go)a do
        assert SnippetGenerator.valid_language?(lang)
      end
    end

    test "returns false for invalid languages" do
      refute SnippetGenerator.valid_language?(:php)
      refute SnippetGenerator.valid_language?(:bash)
    end
  end
end
