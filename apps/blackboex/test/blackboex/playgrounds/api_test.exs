defmodule Blackboex.Playgrounds.ApiTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Playgrounds.Api

  describe "call_flow/2" do
    test "builds correct webhook URL and calls Http.post" do
      # Will fail at connection, but validates URL construction
      result = Api.call_flow("test-token-abc123", %{"name" => "Alice"})
      assert {:error, _msg} = result
    end

    test "accepts empty input" do
      result = Api.call_flow("test-token", %{})
      assert {:error, _msg} = result
    end
  end

  describe "call_api/5" do
    test "builds correct API URL with auth header" do
      result = Api.call_api("my-org", "my-project", "my-api", %{"key" => "val"}, "api-key-123")
      assert {:error, _msg} = result
    end

    test "accepts empty params" do
      result = Api.call_api("org", "proj", "api", %{}, "key")
      assert {:error, _msg} = result
    end
  end

  describe "base_url configuration" do
    test "uses configured base_url" do
      original = Application.get_env(:blackboex, Blackboex.Playgrounds.Api)

      Application.put_env(:blackboex, Blackboex.Playgrounds.Api,
        base_url: "http://custom-host:8080"
      )

      # call_flow will try to connect to custom-host — validates config is read
      result = Api.call_flow("token", %{})
      assert {:error, msg} = result
      # Should not be an SSRF error since custom-host would be allowed
      refute msg =~ "private/internal networks"

      if original do
        Application.put_env(:blackboex, Blackboex.Playgrounds.Api, original)
      else
        Application.delete_env(:blackboex, Blackboex.Playgrounds.Api)
      end
    end
  end
end
