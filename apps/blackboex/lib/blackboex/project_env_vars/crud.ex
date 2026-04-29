defmodule Blackboex.ProjectEnvVars.Crud do
  @moduledoc """
  CRUD operations for generic project env vars (`kind = "env"`).

  All reads are scoped to a single project; listings are filtered to
  `kind = "env"` so generic consumers never see integration-managed rows
  (e.g. the Anthropic key lives under `kind = "llm_anthropic"` and is
  managed by `Blackboex.ProjectEnvVars.LlmKeys`).
  """

  alias Blackboex.Audit
  alias Blackboex.ProjectEnvVars.ProjectEnvVar
  alias Blackboex.ProjectEnvVars.ProjectEnvVarQueries
  alias Blackboex.Repo

  @doc "Lists generic env vars (`kind = \"env\"`) for a project, ordered by name."
  @spec list_env_vars(Ecto.UUID.t()) :: [ProjectEnvVar.t()]
  def list_env_vars(project_id) do
    project_id |> ProjectEnvVarQueries.list_for_project() |> Repo.all()
  end

  @doc "Fetches a single generic env var by project + name. Returns `nil` when not found."
  @spec get_env_var(Ecto.UUID.t(), String.t()) :: ProjectEnvVar.t() | nil
  def get_env_var(project_id, name) do
    project_id |> ProjectEnvVarQueries.by_project_and_name(name, "env") |> Repo.one()
  end

  @doc """
  Returns the decrypted plaintext value for a generic env var by name.

  **Do not expose the return value to end users** — intended for the
  execution engines (API sandbox, Flow runtime, Playground eval).
  """
  @spec get_env_value(Ecto.UUID.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found}
  def get_env_value(project_id, name) do
    case get_env_var(project_id, name) do
      nil -> {:error, :not_found}
      env_var -> {:ok, env_var.encrypted_value}
    end
  end

  @doc """
  Creates a new env var. `kind` defaults to `"env"` when not specified —
  callers that want a different kind must pass it explicitly (this module
  is for generic env vars; LLM keys go through `LlmKeys`).
  """
  @spec create(map()) :: {:ok, ProjectEnvVar.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    attrs = put_default_kind(attrs)

    case %ProjectEnvVar{} |> ProjectEnvVar.changeset(attrs) |> Repo.insert() do
      {:ok, env_var} = ok ->
        Audit.log_async("project_env_var.created", %{
          resource_type: "project_env_var",
          resource_id: env_var.id,
          organization_id: env_var.organization_id,
          project_id: env_var.project_id,
          metadata: %{kind: env_var.kind, name: env_var.name}
        })

        ok

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Updates an env var. Changing `kind` is not allowed — LLM keys are managed
  exclusively through `Blackboex.ProjectEnvVars.LlmKeys`.
  """
  @spec update(ProjectEnvVar.t(), map()) ::
          {:ok, ProjectEnvVar.t()} | {:error, Ecto.Changeset.t()}
  def update(%ProjectEnvVar{} = env_var, attrs) do
    attrs = drop_kind_changes(attrs, env_var.kind)

    case env_var |> ProjectEnvVar.changeset(attrs) |> Repo.update() do
      {:ok, updated} = ok ->
        Audit.log_async("project_env_var.updated", %{
          resource_type: "project_env_var",
          resource_id: updated.id,
          organization_id: updated.organization_id,
          project_id: updated.project_id,
          metadata: %{kind: updated.kind, name: updated.name}
        })

        ok

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Deletes an env var.

  Returns `{:ok, struct}` on success, `{:error, changeset}` on constraint
  failure, or `{:error, :stale}` when the row no longer exists in the
  database (already deleted by another process).
  """
  @spec delete(ProjectEnvVar.t()) ::
          {:ok, ProjectEnvVar.t()} | {:error, Ecto.Changeset.t()} | {:error, :stale}
  def delete(%ProjectEnvVar{} = env_var) do
    case Repo.delete(env_var) do
      {:ok, deleted} = ok ->
        Audit.log_async("project_env_var.deleted", %{
          resource_type: "project_env_var",
          resource_id: deleted.id,
          organization_id: deleted.organization_id,
          project_id: deleted.project_id,
          metadata: %{kind: deleted.kind, name: deleted.name}
        })

        ok

      {:error, _changeset} = error ->
        error
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @doc """
  Loads all generic env vars for a project as a plaintext map
  `%{name => value}` in a single query. Excludes `kind = "llm_anthropic"`.

  Returns `%{}` when the project has no env vars or the project_id is unknown.
  """
  @spec load_runtime_map(Ecto.UUID.t()) :: %{optional(String.t()) => String.t()}
  def load_runtime_map(project_id) do
    project_id
    |> ProjectEnvVarQueries.list_for_project()
    |> Repo.all()
    |> Map.new(fn env_var -> {env_var.name, env_var.encrypted_value} end)
  end

  defp put_default_kind(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :kind) -> attrs
      Map.has_key?(attrs, "kind") -> attrs
      true -> Map.put(attrs, :kind, "env")
    end
  end

  defp drop_kind_changes(attrs, current_kind) when is_map(attrs) do
    attrs = Map.drop(attrs, [:kind, "kind"])

    # Match key type of other keys (don't mix atom/string keys — Ecto.cast rejects)
    case first_key_type(attrs) do
      :atom -> Map.put(attrs, :kind, current_kind)
      :string -> Map.put(attrs, "kind", current_kind)
      :empty -> Map.put(attrs, :kind, current_kind)
    end
  end

  defp first_key_type(map) when map_size(map) == 0, do: :empty

  defp first_key_type(map) do
    {k, _} = Enum.at(map, 0)
    if is_atom(k), do: :atom, else: :string
  end
end
