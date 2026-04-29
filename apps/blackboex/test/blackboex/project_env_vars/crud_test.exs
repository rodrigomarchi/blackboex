defmodule Blackboex.ProjectEnvVars.CrudTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.ProjectEnvVars
  alias Blackboex.ProjectEnvVars.ProjectEnvVar

  setup do
    {_user, org} = user_and_org_fixture()
    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "create/1" do
    test "persists a generic env var", %{org: org, project: project} do
      assert {:ok, %ProjectEnvVar{} = env_var} =
               ProjectEnvVars.create(%{
                 organization_id: org.id,
                 project_id: project.id,
                 name: "API_URL",
                 value: "https://example.com"
               })

      assert env_var.id
      assert env_var.kind == "env"
      assert env_var.encrypted_value == "https://example.com"
    end

    test "returns changeset error with invalid name", %{org: org, project: project} do
      assert {:error, %Ecto.Changeset{}} =
               ProjectEnvVars.create(%{
                 organization_id: org.id,
                 project_id: project.id,
                 name: "bad-name",
                 value: "v"
               })
    end

    test "returns changeset error when value is missing", %{org: org, project: project} do
      assert {:error, %Ecto.Changeset{} = cs} =
               ProjectEnvVars.create(%{
                 organization_id: org.id,
                 project_id: project.id,
                 name: "NO_VALUE"
               })

      assert %{encrypted_value: _} = errors_on(cs)
    end

    test "forces kind=env by default even if attrs omits it", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "NO_KIND",
          value: "v"
        })

      assert env_var.kind == "env"
    end

    test "preserves explicit kind=llm_anthropic when passed", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "ANTHROPIC_API_KEY",
          kind: "llm_anthropic",
          value: "sk-ant-test-xxxxxxxxxxxxxxxxxxxx"
        })

      assert env_var.kind == "llm_anthropic"
    end
  end

  describe "update/2" do
    test "updates value and re-encrypts", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "TOKEN",
          value: "old"
        })

      {:ok, updated} = ProjectEnvVars.update(env_var, %{value: "new"})

      assert updated.encrypted_value == "new"
      refute updated.encrypted_value == env_var.encrypted_value
    end

    test "ignores attempts to change kind", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "T",
          value: "v"
        })

      {:ok, updated} = ProjectEnvVars.update(env_var, %{kind: "llm_anthropic", value: "v"})

      assert updated.kind == "env"
    end

    test "returns error on invalid name", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "OK",
          value: "v"
        })

      assert {:error, %Ecto.Changeset{}} =
               ProjectEnvVars.update(env_var, %{name: "bad-name", value: "v"})
    end
  end

  describe "delete/1" do
    test "removes the row", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "RM",
          value: "v"
        })

      assert {:ok, _} = ProjectEnvVars.delete(env_var)
      assert is_nil(ProjectEnvVars.get_env_var(project.id, "RM"))
    end

    test "returns stale error when row already deleted", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "GONE",
          value: "v"
        })

      assert {:ok, _} = ProjectEnvVars.delete(env_var)
      # Second delete on the same stale struct returns {:error, :stale}
      assert {:error, :stale} = ProjectEnvVars.delete(env_var)
    end
  end

  describe "get_env_var/2" do
    test "returns the struct for a kind=env row", %{project: project} do
      env_var = project_env_var_fixture(%{project_id: project.id, name: "FETCH", value: "v"})

      assert %ProjectEnvVar{id: id, name: "FETCH"} =
               ProjectEnvVars.get_env_var(project.id, "FETCH")

      assert id == env_var.id
    end

    test "returns nil when name is unknown", %{project: project} do
      assert is_nil(ProjectEnvVars.get_env_var(project.id, "MISSING"))
    end

    test "does NOT return kind=llm_anthropic rows", %{project: project} do
      llm_anthropic_key_fixture(%{project_id: project.id})
      assert is_nil(ProjectEnvVars.get_env_var(project.id, "ANTHROPIC_API_KEY"))
    end
  end

  describe "get_env_value/2" do
    test "returns decrypted plaintext", %{project: project} do
      project_env_var_fixture(%{project_id: project.id, name: "DB_PASS", value: "super"})
      assert {:ok, "super"} = ProjectEnvVars.get_env_value(project.id, "DB_PASS")
    end

    test "returns not_found for unknown", %{project: project} do
      assert {:error, :not_found} = ProjectEnvVars.get_env_value(project.id, "MISSING")
    end
  end

  describe "list_env_vars/1" do
    test "returns only kind=env rows ordered by name", %{project: project} do
      project_env_var_fixture(%{project_id: project.id, name: "Z_KEY", value: "v"})
      project_env_var_fixture(%{project_id: project.id, name: "A_KEY", value: "v"})
      llm_anthropic_key_fixture(%{project_id: project.id})

      names = ProjectEnvVars.list_env_vars(project.id) |> Enum.map(& &1.name)
      assert names == ["A_KEY", "Z_KEY"]
    end

    test "returns [] when project has no env vars", %{project: project} do
      assert ProjectEnvVars.list_env_vars(project.id) == []
    end

    test "isolates env vars between projects", %{org: org, project: project} do
      {_user2, org2} = user_and_org_fixture()
      project2 = Blackboex.Projects.get_default_project(org2.id)

      project_env_var_fixture(%{
        project_id: project.id,
        organization_id: org.id,
        name: "SHARED",
        value: "a"
      })

      project_env_var_fixture(%{
        project_id: project2.id,
        organization_id: org2.id,
        name: "SHARED",
        value: "b"
      })

      assert [%{name: "SHARED"}] = ProjectEnvVars.list_env_vars(project.id)
      assert [%{name: "SHARED"}] = ProjectEnvVars.list_env_vars(project2.id)
    end
  end

  describe "load_runtime_map/1" do
    test "returns %{name => plaintext} with all kind=env rows", %{project: project} do
      project_env_var_fixture(%{project_id: project.id, name: "A", value: "1"})
      project_env_var_fixture(%{project_id: project.id, name: "B", value: "2"})

      assert ProjectEnvVars.load_runtime_map(project.id) == %{"A" => "1", "B" => "2"}
    end

    test "excludes llm_anthropic rows", %{project: project} do
      project_env_var_fixture(%{project_id: project.id, name: "X", value: "1"})
      llm_anthropic_key_fixture(%{project_id: project.id})

      assert ProjectEnvVars.load_runtime_map(project.id) == %{"X" => "1"}
    end

    test "returns empty map for a project with no env vars", %{project: project} do
      assert ProjectEnvVars.load_runtime_map(project.id) == %{}
    end

    test "returns empty map for an unknown project_id" do
      assert ProjectEnvVars.load_runtime_map(Ecto.UUID.generate()) == %{}
    end
  end

  describe "audit events" do
    test "create emits an audit log with masked metadata", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "AUD",
          value: "secret"
        })

      logs = Blackboex.Audit.list_logs(org.id)
      entry = Enum.find(logs, fn log -> log.action == "project_env_var.created" end)
      assert entry
      assert entry.resource_id == env_var.id
      refute entry.metadata["value"] == "secret"
      refute inspect(entry.metadata) =~ "secret"
    end

    test "update emits an audit log", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "UP",
          value: "old"
        })

      {:ok, _} = ProjectEnvVars.update(env_var, %{value: "new"})

      logs = Blackboex.Audit.list_logs(org.id)
      assert Enum.any?(logs, fn log -> log.action == "project_env_var.updated" end)
    end

    test "delete emits an audit log", %{org: org, project: project} do
      {:ok, env_var} =
        ProjectEnvVars.create(%{
          organization_id: org.id,
          project_id: project.id,
          name: "DEL",
          value: "v"
        })

      {:ok, _} = ProjectEnvVars.delete(env_var)

      logs = Blackboex.Audit.list_logs(org.id)
      assert Enum.any?(logs, fn log -> log.action == "project_env_var.deleted" end)
    end
  end
end
