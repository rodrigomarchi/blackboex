defmodule Blackboex.Features do
  @moduledoc """
  Canonical feature flag facade. Resolution order, first-wins:

    1. Per-project `Blackboex.ProjectEnvVars` override
       (`name = "FEATURE_PROJECT_AGENT"`, value `"true"` / `"false"`).
    2. Application config default — `:blackboex, :features` keyword list,
       e.g. `Application.get_env(:blackboex, :features)[:project_agent]`.
    3. Hard-coded conservative default (`false`).

  This is the canonical pattern for adding new feature flags. Keep this
  module thin (<30 LOC of logic) so each new flag is a one-line addition.
  """

  alias Blackboex.ProjectEnvVars
  alias Blackboex.Projects.Project

  @env_var_name "FEATURE_PROJECT_AGENT"

  @doc """
  Returns whether the Project Agent is enabled for the given project.
  See module doc for the resolution order.
  """
  @spec project_agent_enabled?(Project.t()) :: boolean()
  def project_agent_enabled?(%Project{} = project) do
    case override(project) do
      {:ok, value} -> value
      :no_override -> config_default(:project_agent, false)
    end
  end

  @spec override(Project.t()) :: {:ok, boolean()} | :no_override
  defp override(%Project{id: project_id}) do
    case ProjectEnvVars.get_env_value(project_id, @env_var_name) do
      {:ok, "true"} -> {:ok, true}
      {:ok, "false"} -> {:ok, false}
      _ -> :no_override
    end
  end

  @spec config_default(atom(), boolean()) :: boolean()
  defp config_default(key, fallback) do
    :blackboex
    |> Application.get_env(:features, [])
    |> Keyword.get(key, fallback)
  end
end
