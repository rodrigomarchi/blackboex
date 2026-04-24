defmodule Blackboex.ProjectEnvVars.ProjectEnvVarQueries do
  @moduledoc """
  Composable query builders for the ProjectEnvVar schema.

  All functions return `Ecto.Query.t()` values — no `Repo` calls, no side
  effects. Callers in the sub-contexts are responsible for execution.
  """

  import Ecto.Query, warn: false

  alias Blackboex.ProjectEnvVars.ProjectEnvVar

  @doc "Generic env vars (`kind = \"env\"`) for a project, ordered by name."
  @spec list_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_project(project_id) do
    ProjectEnvVar
    |> where([v], v.project_id == ^project_id and v.kind == "env")
    |> order_by([v], asc: v.name)
  end

  @doc "All env vars for a project (any `kind`), ordered by name."
  @spec list_all_for_project(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_all_for_project(project_id) do
    ProjectEnvVar
    |> where([v], v.project_id == ^project_id)
    |> order_by([v], asc: v.name)
  end

  @doc "Single env var by project + name, optionally filtered by kind."
  @spec by_project_and_name(Ecto.UUID.t(), String.t(), String.t()) :: Ecto.Query.t()
  def by_project_and_name(project_id, name, kind \\ "env") do
    ProjectEnvVar
    |> where([v], v.project_id == ^project_id and v.name == ^name and v.kind == ^kind)
  end

  @doc "All env vars for a project filtered by `kind`."
  @spec by_project_and_kind(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_project_and_kind(project_id, kind) do
    ProjectEnvVar
    |> where([v], v.project_id == ^project_id and v.kind == ^kind)
    |> order_by([v], asc: v.name)
  end
end
