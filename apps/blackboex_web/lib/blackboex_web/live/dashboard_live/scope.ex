defmodule BlackboexWeb.DashboardLive.Scope do
  @moduledoc """
  Scope helpers for dashboard LiveViews.

  Each dashboard tab (Overview, APIs, Flows, LLM, Usage) runs in either an
  organization scope or a project scope. These helpers resolve the current
  scope from the socket's `current_scope` assign and build the corresponding
  URL prefix used by `DashboardNav`.
  """

  alias Blackboex.Accounts.Scope, as: AccountsScope
  alias Blackboex.Organizations.Organization
  alias Blackboex.Projects.Project

  @type scope :: {:org, binary()} | {:project, binary()}

  @doc """
  Resolves the dashboard scope from a LiveView socket and route params.

  When `params` contains a `"project_slug"`, the URL is project-scoped and
  this returns `{:project, id}` from the socket's project assign. When only
  `"org_slug"` is present, returns `{:org, id}` from the socket's
  organization assign. Returns `nil` when no scope can be resolved.
  """
  @spec from_socket(Phoenix.LiveView.Socket.t(), map()) :: scope() | nil
  def from_socket(socket, params \\ %{})

  def from_socket(%{assigns: %{current_scope: %AccountsScope{} = scope}}, params) do
    cond do
      Map.has_key?(params, "project_slug") and match?(%Project{}, scope.project) ->
        {:project, scope.project.id}

      match?(%Organization{}, scope.organization) ->
        {:org, scope.organization.id}

      true ->
        nil
    end
  end

  def from_socket(_socket, _params), do: nil

  @doc """
  Returns the `/dashboard` URL prefix for the given scope.
  """
  @spec base_path(scope(), Organization.t(), Project.t() | nil) :: String.t()
  def base_path({:project, _id}, %Organization{slug: org_slug}, %Project{slug: project_slug}) do
    "/orgs/#{org_slug}/projects/#{project_slug}/dashboard"
  end

  def base_path({:org, _id}, %Organization{slug: org_slug}, _project) do
    "/orgs/#{org_slug}/dashboard"
  end
end
