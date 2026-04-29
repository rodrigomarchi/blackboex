defmodule Blackboex.ProjectEnvVarsFixtures do
  @moduledoc """
  Test helpers for creating ProjectEnvVar entities.

  Provides fixtures for the two supported kinds:

    * `project_env_var_fixture/1` — generic env vars (`kind = "env"`)
    * `llm_anthropic_key_fixture/1` — project-scoped Anthropic API key (`kind = "llm_anthropic"`)
  """

  alias Blackboex.ProjectEnvVars

  @doc """
  Creates a generic project env var (`kind = "env"`) for the given project.

  If no `project_id` / `organization_id` is provided, creates an org and uses
  its default project automatically.

  ## Options

    * `:organization_id` - owning org UUID (default: auto-created)
    * `:project_id` - owning project UUID (default: default project of the org)
    * `:name` - env var name (default: auto-generated, e.g. `"ENV_VAR_42"`)
    * `:value` - plaintext value (default: auto-generated, e.g. `"value-42"`)
    * `:kind` - env var kind (default: `"env"`)

  Returns the `%ProjectEnvVar{}` struct.
  """
  @spec project_env_var_fixture(map()) :: Blackboex.ProjectEnvVars.ProjectEnvVar.t()
  def project_env_var_fixture(attrs \\ %{}) do
    {org_id, project_id} = org_and_project(attrs)
    uid = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    {:ok, env_var} =
      create_for_kind(attrs[:kind] || "env", %{
        organization_id: org_id,
        project_id: project_id,
        name: attrs[:name] || "ENV_VAR_#{uid}",
        value: attrs[:value] || "value-#{uid}"
      })

    env_var
  end

  @doc """
  Creates a project-scoped Anthropic API key (`kind = "llm_anthropic"`, name
  fixed as `"ANTHROPIC_API_KEY"`).

  ## Options

    * `:organization_id` - owning org UUID (default: auto-created)
    * `:project_id` - owning project UUID (default: default project of the org)
    * `:value` - plaintext key (default: `"sk-ant-test-xxxxxxxxxxxxxxxxxxxx"`)

  Returns the `%ProjectEnvVar{}` struct.
  """
  @spec llm_anthropic_key_fixture(map()) :: Blackboex.ProjectEnvVars.ProjectEnvVar.t()
  def llm_anthropic_key_fixture(attrs \\ %{}) do
    {org_id, project_id} = org_and_project(attrs)

    {:ok, env_var} =
      create_for_kind("llm_anthropic", %{
        organization_id: org_id,
        project_id: project_id,
        name: "ANTHROPIC_API_KEY",
        value: attrs[:value] || "sk-ant-test-xxxxxxxxxxxxxxxxxxxx"
      })

    env_var
  end

  defp org_and_project(attrs) do
    org_id =
      attrs[:organization_id] ||
        Blackboex.OrganizationsFixtures.org_fixture().id

    project_id =
      attrs[:project_id] ||
        (Blackboex.Projects.get_default_project(org_id) || %{id: nil}).id

    {org_id, project_id}
  end

  defp create_for_kind("env", base_attrs) do
    ProjectEnvVars.create(base_attrs)
  end

  defp create_for_kind(kind, base_attrs) do
    ProjectEnvVars.create(Map.put(base_attrs, :kind, kind))
  end
end
