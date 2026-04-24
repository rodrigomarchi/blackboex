defmodule Blackboex.ProjectEnvVars do
  @moduledoc """
  The ProjectEnvVars context. Stores project-scoped env vars and integration
  keys (currently: Anthropic API key). Unified replacement for the legacy
  `FlowSecrets` context — generic env vars live under `kind = "env"` and are
  injected into API, Flow, and Playground runtimes at execution time.

  Split into sub-contexts:

    * `Blackboex.ProjectEnvVars.Crud` — generic env var CRUD (`kind = "env"`)
    * `Blackboex.ProjectEnvVars.LlmKeys` — Anthropic-scoped key lifecycle
      (`kind = "llm_anthropic"`)

  External callers (web, workers, runtimes) go through THIS module only —
  the sub-contexts are implementation details.
  """

  alias Blackboex.ProjectEnvVars.Crud
  alias Blackboex.ProjectEnvVars.LlmKeys
  alias Blackboex.ProjectEnvVars.ProjectEnvVar

  @type provider :: :anthropic

  # ── Generic env var CRUD ───────────────────────────────────────────────────

  defdelegate list_env_vars(project_id), to: Crud
  defdelegate get_env_var(project_id, name), to: Crud
  defdelegate get_env_value(project_id, name), to: Crud
  defdelegate create(attrs), to: Crud
  defdelegate update(env_var, attrs), to: Crud
  defdelegate delete(env_var), to: Crud
  defdelegate load_runtime_map(project_id), to: Crud

  # ── LLM integration keys ───────────────────────────────────────────────────

  defdelegate get_llm_key(project_id, provider), to: LlmKeys
  defdelegate get_masked_key(project_id, provider), to: LlmKeys
  defdelegate put_llm_key(project_id, provider, value, organization_id), to: LlmKeys
  defdelegate delete_llm_key(project_id, provider), to: LlmKeys

  @doc """
  Convenience `change/2` wrapper for the schema changeset — useful in
  LiveView forms that need to render errors.
  """
  @spec change(ProjectEnvVar.t(), map()) :: Ecto.Changeset.t()
  def change(%ProjectEnvVar{} = env_var, attrs \\ %{}) do
    ProjectEnvVar.changeset(env_var, attrs)
  end
end
