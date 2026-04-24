defmodule Blackboex.ProjectEnvVars.LlmKeysTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.ProjectEnvVars

  setup do
    {_user, org} = user_and_org_fixture()
    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "get_llm_key/2" do
    test ":not_configured when no key exists", %{project: project} do
      assert {:error, :not_configured} = ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "returns the plaintext value after put_llm_key/4", %{org: org, project: project} do
      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-abc-xxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      assert {:ok, "sk-ant-abc-xxxxxxxxxxxxxxxxxxxx"} =
               ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "does not emit an audit log (read-only)", %{org: org, project: project} do
      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-read-xxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      # Clear knowledge of pre-existing logs
      logs_before = Blackboex.Audit.list_logs(org.id)
      count_before = length(logs_before)

      ProjectEnvVars.get_llm_key(project.id, :anthropic)

      logs_after = Blackboex.Audit.list_logs(org.id)
      assert length(logs_after) == count_before
    end

    test "unsupported provider", %{project: project} do
      assert {:error, :provider_not_supported} =
               ProjectEnvVars.get_llm_key(project.id, :openai)
    end
  end

  describe "put_llm_key/4" do
    test "creates a new row on first call", %{org: org, project: project} do
      assert {:ok, env_var} =
               ProjectEnvVars.put_llm_key(
                 project.id,
                 :anthropic,
                 "sk-ant-first-xxxxxxxxxxxxxxxxxxxx",
                 org.id
               )

      assert env_var.kind == "llm_anthropic"
      assert env_var.name == "ANTHROPIC_API_KEY"
    end

    test "rejects embedded control characters in key", %{org: org, project: project} do
      assert {:error, %Ecto.Changeset{}} =
               ProjectEnvVars.put_llm_key(
                 project.id,
                 :anthropic,
                 "sk-ant-ok-xxxxxxxxxxxxxxxxxxxx\n",
                 org.id
               )
    end

    test "upserts — second call updates the existing row", %{org: org, project: project} do
      {:ok, first} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-old-xxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      {:ok, second} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-new-xxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      assert first.id == second.id

      assert {:ok, "sk-ant-new-xxxxxxxxxxxxxxxxxxxx"} =
               ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "independent projects keep separate keys", %{org: org, project: project} do
      {_user2, org2} = user_and_org_fixture()
      project2 = Blackboex.Projects.get_default_project(org2.id)

      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-A-xxxxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project2.id,
          :anthropic,
          "sk-ant-B-xxxxxxxxxxxxxxxxxxxxxx",
          org2.id
        )

      assert {:ok, "sk-ant-A-xxxxxxxxxxxxxxxxxxxxxx"} =
               ProjectEnvVars.get_llm_key(project.id, :anthropic)

      assert {:ok, "sk-ant-B-xxxxxxxxxxxxxxxxxxxxxx"} =
               ProjectEnvVars.get_llm_key(project2.id, :anthropic)
    end

    test "unsupported provider", %{org: org, project: project} do
      assert {:error, :provider_not_supported} =
               ProjectEnvVars.put_llm_key(project.id, :openai, "sk-x", org.id)
    end

    test "emits an audit event with masked metadata", %{org: org, project: project} do
      plaintext = "sk-ant-super-secret-xxxxxxxxxxxxxxxxxxxx"
      {:ok, env_var} = ProjectEnvVars.put_llm_key(project.id, :anthropic, plaintext, org.id)

      logs = Blackboex.Audit.list_logs(org.id)
      entry = Enum.find(logs, fn log -> log.action == "project_llm_key.set" end)
      assert entry
      assert entry.resource_id == env_var.id
      refute inspect(entry.metadata) =~ plaintext
    end
  end

  describe "delete_llm_key/2" do
    test "no-op when no key exists (idempotent)", %{project: project} do
      assert :ok = ProjectEnvVars.delete_llm_key(project.id, :anthropic)
      assert {:error, :not_configured} = ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "removes the row", %{org: org, project: project} do
      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-rm-xxxxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      assert :ok = ProjectEnvVars.delete_llm_key(project.id, :anthropic)
      assert {:error, :not_configured} = ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "idempotent when called twice — does not raise StaleEntryError", %{
      org: org,
      project: project
    } do
      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-twice-xxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      assert :ok = ProjectEnvVars.delete_llm_key(project.id, :anthropic)
      # Second delete must not crash (race-safe)
      assert :ok = ProjectEnvVars.delete_llm_key(project.id, :anthropic)
    end

    test "emits an audit event", %{org: org, project: project} do
      {:ok, _} =
        ProjectEnvVars.put_llm_key(
          project.id,
          :anthropic,
          "sk-ant-audit-xxxxxxxxxxxxxxxxxxxx",
          org.id
        )

      :ok = ProjectEnvVars.delete_llm_key(project.id, :anthropic)

      logs = Blackboex.Audit.list_logs(org.id)
      assert Enum.any?(logs, fn log -> log.action == "project_llm_key.deleted" end)
    end

    test "unsupported provider", %{project: project} do
      assert {:error, :provider_not_supported} =
               ProjectEnvVars.delete_llm_key(project.id, :openai)
    end
  end
end
