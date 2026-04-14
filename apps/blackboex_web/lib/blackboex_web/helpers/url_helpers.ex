defmodule BlackboexWeb.Helpers.UrlHelpers do
  @moduledoc """
  Centralized URL helpers for slug-based paths.

  All platform URLs follow the pattern:
    /orgs/:org_slug/projects/:project_slug/...

  Use these functions everywhere instead of hardcoding paths to keep
  routes consistent when slugs change.
  """

  @doc "Returns the org dashboard path."
  @spec org_path(String.t()) :: String.t()
  def org_path(org_slug), do: "/orgs/#{org_slug}"

  @doc "Returns the project dashboard path."
  @spec project_path(String.t(), String.t()) :: String.t()
  def project_path(org_slug, project_slug),
    do: "/orgs/#{org_slug}/projects/#{project_slug}"

  @doc "Returns the API show path within a project."
  @spec api_path(String.t(), String.t(), String.t()) :: String.t()
  def api_path(org_slug, project_slug, api_slug),
    do: "/orgs/#{org_slug}/projects/#{project_slug}/apis/#{api_slug}"

  @doc """
  Returns the API editor path for a specific tab.

  Valid tabs: `\"chat\"`, `\"validation\"`, `\"run\"`, `\"metrics\"`, `\"publish\"`, `\"info\"`.
  """
  @spec api_edit_path(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def api_edit_path(org_slug, project_slug, api_slug, tab),
    do: "/orgs/#{org_slug}/projects/#{project_slug}/apis/#{api_slug}/edit/#{tab}"
end
