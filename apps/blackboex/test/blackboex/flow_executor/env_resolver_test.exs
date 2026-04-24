defmodule Blackboex.FlowExecutor.EnvResolverTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.EnvResolver

  setup do
    {_user, org} = user_and_org_fixture()
    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "resolve/2 — canonical {{env.NAME}}" do
    test "resolves a single env placeholder", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "openai_key",
        value: "sk-real-123"
      })

      definition = %{
        "nodes" => %{
          "1" => %{"data" => %{"api_key" => "{{env.openai_key}}"}}
        }
      }

      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert get_in(resolved, ["nodes", "1", "data", "api_key"]) == "sk-real-123"
    end

    test "resolves repeated env in same string", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "X",
        value: "vx"
      })

      definition = %{"data" => "{{env.X}}-{{env.X}}"}

      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert resolved["data"] == "vx-vx"
    end

    test "resolves env refs in nested map", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "TOKEN",
        value: "my-token"
      })

      definition = %{
        "nodes" => %{"1" => %{"data" => %{"headers" => %{"auth" => "Bearer {{env.TOKEN}}"}}}}
      }

      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)

      assert get_in(resolved, ["nodes", "1", "data", "headers", "auth"]) ==
               "Bearer my-token"
    end

    test "resolves env refs in list values", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "URL",
        value: "http://example.com"
      })

      definition = %{"list" => [%{"url" => "{{env.URL}}"}]}

      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert get_in(resolved, ["list", Access.at(0), "url"]) == "http://example.com"
    end

    test "passes through definition with no placeholders unchanged", %{project: project} do
      definition = %{"nodes" => %{"1" => %{"data" => %{"url" => "https://example.com"}}}}

      assert {:ok, ^definition} = EnvResolver.resolve(definition, project.id)
    end

    test "empty definition returns empty map", %{project: project} do
      assert {:ok, %{}} = EnvResolver.resolve(%{}, project.id)
    end

    test "preserves nil values in fields", %{project: project} do
      definition = %{"data" => %{"key" => nil}}
      assert {:ok, %{"data" => %{"key" => nil}}} = EnvResolver.resolve(definition, project.id)
    end
  end

  describe "resolve/2 — legacy {{secrets.NAME}} alias" do
    test "resolves legacy secrets placeholder", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "legacy_key",
        value: "legacy-value"
      })

      definition = %{"data" => %{"k" => "{{secrets.legacy_key}}"}}

      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert get_in(resolved, ["data", "k"]) == "legacy-value"
    end

    test "resolves mixed env and secrets in same string", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "A",
        value: "valA"
      })

      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "B",
        value: "valB"
      })

      definition = %{"data" => "{{env.A}}-{{secrets.B}}"}

      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert resolved["data"] == "valA-valB"
    end
  end

  describe "resolve/2 — regex edge cases" do
    test "does not match {{env.X-Y}} (hyphen)", %{project: project} do
      definition = %{"data" => "{{env.X-Y}}"}
      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert resolved["data"] == "{{env.X-Y}}"
    end

    test "does not match {{env.}} (empty name)", %{project: project} do
      definition = %{"data" => "{{env.}}"}
      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert resolved["data"] == "{{env.}}"
    end

    test "does not match {{ env.X }} (spaces)", %{project: project} do
      definition = %{"data" => "{{ env.X }}"}
      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert resolved["data"] == "{{ env.X }}"
    end

    test "matches lowercase names", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "lowercase",
        value: "lv"
      })

      definition = %{"data" => "{{env.lowercase}}"}
      assert {:ok, resolved} = EnvResolver.resolve(definition, project.id)
      assert resolved["data"] == "lv"
    end
  end

  describe "resolve/2 — errors" do
    test "returns missing_env error when referenced var does not exist", %{project: project} do
      definition = %{"data" => %{"api_key" => "{{env.missing_key}}"}}

      assert {:error, {:missing_env, "missing_key"}} =
               EnvResolver.resolve(definition, project.id)
    end

    test "fails fast on first missing env (legacy placeholder)", %{project: project} do
      definition = %{"data" => %{"api_key" => "{{secrets.other_key}}"}}

      assert {:error, {:missing_env, "other_key"}} =
               EnvResolver.resolve(definition, project.id)
    end

    test "isolates by project_id — var in another project is not visible", %{project: project} do
      # Create a var in a *different* project (different org)
      {_user2, org2} = user_and_org_fixture()
      project2 = Blackboex.Projects.get_default_project(org2.id)

      project_env_var_fixture(%{
        organization_id: org2.id,
        project_id: project2.id,
        name: "cross_org",
        value: "nope"
      })

      definition = %{"data" => %{"k" => "{{env.cross_org}}"}}

      assert {:error, {:missing_env, "cross_org"}} =
               EnvResolver.resolve(definition, project.id)
    end
  end

  describe "redact/2" do
    test "replaces values back to canonical {{env.NAME}}" do
      definition = %{"data" => %{"api_key" => "sk-real-123"}}
      env_values = %{"openai_key" => "sk-real-123"}

      redacted = EnvResolver.redact(definition, env_values)
      assert get_in(redacted, ["data", "api_key"]) == "{{env.openai_key}}"
    end

    test "redacts multiple distinct values" do
      definition = %{"data" => %{"a" => "value_alpha_xyz", "b" => "value_beta_xyz"}}
      env_values = %{"key_a" => "value_alpha_xyz", "key_b" => "value_beta_xyz"}

      redacted = EnvResolver.redact(definition, env_values)
      assert get_in(redacted, ["data", "a"]) == "{{env.key_a}}"
      assert get_in(redacted, ["data", "b"]) == "{{env.key_b}}"
    end

    test "leaves values unchanged when no match" do
      definition = %{"data" => %{"url" => "https://example.com"}}
      redacted = EnvResolver.redact(definition, %{"other" => "zzzzzzzz"})
      assert get_in(redacted, ["data", "url"]) == "https://example.com"
    end

    test "redacts both occurrences when value appears multiple times" do
      definition = %{"data" => %{"v" => "secret42secret42"}}
      redacted = EnvResolver.redact(definition, %{"K" => "secret42"})
      assert get_in(redacted, ["data", "v"]) == "{{env.K}}{{env.K}}"
    end

    test "treats env value as literal string (not regex)" do
      definition = %{"data" => %{"v" => "abc.*pattern.*def"}}
      redacted = EnvResolver.redact(definition, %{"PATTERN" => ".*pattern.*"})
      assert get_in(redacted, ["data", "v"]) == "abc{{env.PATTERN}}def"
    end

    test "does not redact values shorter than the redact threshold (8 bytes)" do
      definition = %{"data" => %{"v" => "GET HTTP/1.1"}}
      redacted = EnvResolver.redact(definition, %{"METHOD" => "GET"})
      # "GET" (3 bytes) is below the redact threshold; must remain literal.
      assert get_in(redacted, ["data", "v"]) == "GET HTTP/1.1"
    end

    test "redacts inside nested structures" do
      definition = %{
        "list" => [%{"x" => "Bearer my-token"}],
        "map" => %{"k" => %{"y" => "my-token"}}
      }

      redacted = EnvResolver.redact(definition, %{"T" => "my-token"})
      assert get_in(redacted, ["list", Access.at(0), "x"]) == "Bearer {{env.T}}"
      assert get_in(redacted, ["map", "k", "y"]) == "{{env.T}}"
    end
  end
end
