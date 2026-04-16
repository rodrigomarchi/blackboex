defmodule BlackboexWeb.LastVisited do
  @moduledoc """
  Resolves the organization/project a user should land on after authenticating.

  Order of preference:
    1. The user's persisted `last_organization_id` + `last_project_id` (if the
       user still has access to both).
    2. The persisted `last_organization_id` alone with its Default project.
    3. The first organization the user belongs to with its Default project.
    4. The first organization only, when no project is reachable.
    5. `:none` when the user has no organizations (should not happen in
       practice — registration seeds a personal org + Default project).
  """

  alias Blackboex.Accounts.User
  alias Blackboex.Organizations
  alias Blackboex.Organizations.Organization
  alias Blackboex.Projects
  alias Blackboex.Projects.Project

  @type result ::
          {:ok, Organization.t(), Project.t()}
          | {:org_only, Organization.t()}
          | :none

  @spec resolve(User.t()) :: result()
  def resolve(%User{} = user) do
    with {:last_org, %Organization{} = org} <- last_org_for(user),
         true <- has_org_membership?(org, user) do
      resolve_with_org(user, org)
    else
      _ -> fallback_first_org(user)
    end
  end

  defp last_org_for(%User{last_organization_id: nil}), do: {:last_org, nil}

  defp last_org_for(%User{last_organization_id: id}) do
    {:last_org, Organizations.get_organization(id)}
  end

  defp has_org_membership?(%Organization{} = org, %User{} = user) do
    Organizations.get_user_membership(org, user) != nil
  end

  defp resolve_with_org(%User{last_project_id: nil} = _user, %Organization{} = org) do
    with_default_project(org)
  end

  defp resolve_with_org(%User{last_project_id: project_id} = user, %Organization{} = org) do
    case Projects.get_project(org.id, project_id) do
      nil ->
        with_default_project(org)

      %Project{} = project ->
        if user_can_access_project?(user, org, project) do
          {:ok, org, project}
        else
          with_default_project(org)
        end
    end
  end

  defp with_default_project(%Organization{} = org) do
    case Projects.get_default_project(org.id) do
      nil -> {:org_only, org}
      %Project{} = project -> {:ok, org, project}
    end
  end

  defp user_can_access_project?(%User{} = user, %Organization{} = org, %Project{} = project) do
    case Organizations.get_user_membership(org, user) do
      nil ->
        false

      membership ->
        membership.role in [:owner, :admin] or
          Projects.get_project_membership(project, user) != nil
    end
  end

  defp fallback_first_org(%User{} = user) do
    case Organizations.list_user_organizations(user) do
      [%Organization{} = org | _] -> with_default_project(org)
      [] -> :none
    end
  end
end
