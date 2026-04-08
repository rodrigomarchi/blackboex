defmodule Blackboex.FlowExecutor.SecretResolverTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.SecretResolver

  setup do
    {_user, org} = user_and_org_fixture()
    %{org: org}
  end

  describe "resolve/2" do
    test "resolves a single secret placeholder", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "openai_key", value: "sk-real-123"})

      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"api_key" => "{{secrets.openai_key}}"}}
        }
      }

      assert {:ok, resolved} = SecretResolver.resolve(definition, org.id)
      assert get_in(resolved, ["nodes", "1", "data", "api_key"]) == "sk-real-123"
    end

    test "returns error when secret does not exist", %{org: org} do
      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"api_key" => "{{secrets.missing_key}}"}}
        }
      }

      assert {:error, {:missing_secret, "missing_key"}} =
               SecretResolver.resolve(definition, org.id)
    end

    test "passes through definition with no secret refs unchanged", %{org: org} do
      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"url" => "https://example.com", "timeout" => 30}}
        }
      }

      assert {:ok, ^definition} = SecretResolver.resolve(definition, org.id)
    end

    test "resolves multiple secrets in the same definition", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "key_a", value: "value_a"})
      flow_secret_fixture(%{organization_id: org.id, name: "key_b", value: "value_b"})

      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"a" => "{{secrets.key_a}}"}},
          "2" => %{"data" => %{"b" => "{{secrets.key_b}}"}}
        }
      }

      assert {:ok, resolved} = SecretResolver.resolve(definition, org.id)
      assert get_in(resolved, ["nodes", "1", "data", "a"]) == "value_a"
      assert get_in(resolved, ["nodes", "2", "data", "b"]) == "value_b"
    end

    test "resolves secret refs in nested data values", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "token", value: "my-token"})

      definition = %{
        "nodes" => %{
          "1" => %{
            "data" => %{
              "headers" => %{
                "Authorization" => "Bearer {{secrets.token}}"
              }
            }
          }
        }
      }

      assert {:ok, resolved} = SecretResolver.resolve(definition, org.id)

      assert get_in(resolved, ["nodes", "1", "data", "headers", "Authorization"]) ==
               "Bearer my-token"
    end

    test "resolves same secret referenced multiple times", %{org: org} do
      flow_secret_fixture(%{organization_id: org.id, name: "shared", value: "shared_val"})

      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"x" => "{{secrets.shared}}"}},
          "2" => %{"data" => %{"y" => "{{secrets.shared}}"}}
        }
      }

      assert {:ok, resolved} = SecretResolver.resolve(definition, org.id)
      assert get_in(resolved, ["nodes", "1", "data", "x"]) == "shared_val"
      assert get_in(resolved, ["nodes", "2", "data", "y"]) == "shared_val"
    end

    test "does not resolve secrets from a different org", %{org: org} do
      {_user2, org2} = user_and_org_fixture()
      flow_secret_fixture(%{organization_id: org2.id, name: "other_key", value: "should_not_see"})

      definition = %{"nodes" => %{"1" => %{"data" => %{"k" => "{{secrets.other_key}}"}}}}

      assert {:error, {:missing_secret, "other_key"}} = SecretResolver.resolve(definition, org.id)
    end
  end

  describe "redact/2" do
    test "replaces secret values back to placeholders" do
      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"api_key" => "sk-real-123"}}
        }
      }

      secret_values = %{"openai_key" => "sk-real-123"}

      redacted = SecretResolver.redact(definition, secret_values)
      assert get_in(redacted, ["nodes", "1", "data", "api_key"]) == "{{secrets.openai_key}}"
    end

    test "redacts multiple secrets" do
      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"a" => "value_a", "b" => "value_b"}}
        }
      }

      secret_values = %{"key_a" => "value_a", "key_b" => "value_b"}

      redacted = SecretResolver.redact(definition, secret_values)
      assert get_in(redacted, ["nodes", "1", "data", "a"]) == "{{secrets.key_a}}"
      assert get_in(redacted, ["nodes", "1", "data", "b"]) == "{{secrets.key_b}}"
    end

    test "leaves non-secret values unchanged" do
      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"url" => "https://example.com"}}
        }
      }

      redacted = SecretResolver.redact(definition, %{"some_key" => "other_value"})
      assert get_in(redacted, ["nodes", "1", "data", "url"]) == "https://example.com"
    end

    test "redacts value embedded in a longer string" do
      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"header" => "Bearer my-token"}}
        }
      }

      secret_values = %{"token" => "my-token"}

      redacted = SecretResolver.redact(definition, secret_values)
      assert get_in(redacted, ["nodes", "1", "data", "header"]) == "Bearer {{secrets.token}}"
    end
  end
end
