defmodule Blackboex.Projects.ProjectQueries do
  @moduledoc """
  Query builders for Projects. Only contains query builders -- no Repo calls.
  """
  import Ecto.Query, warn: false

  alias Blackboex.Organizations.Membership
  alias Blackboex.Projects.{Project, ProjectMembership}

  @spec for_organization(Ecto.UUID.t()) :: Ecto.Query.t()
  def for_organization(org_id) do
    from p in Project, where: p.organization_id == ^org_id
  end

  @spec by_org_and_slug(Ecto.UUID.t(), String.t()) :: Ecto.Query.t()
  def by_org_and_slug(org_id, slug) do
    from p in Project,
      where: p.organization_id == ^org_id and p.slug == ^slug
  end

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(org_id, project_id) do
    from p in Project,
      where: p.organization_id == ^org_id and p.id == ^project_id
  end

  @doc """
  Returns projects accessible to a user:
  - Projects where user has a ProjectMembership, OR
  - ALL projects if user is org owner or admin
  """
  @spec for_user(Ecto.UUID.t(), integer()) :: Ecto.Query.t()
  def for_user(org_id, user_id) do
    org_privileged_query =
      from m in Membership,
        where:
          m.organization_id == ^org_id and
            m.user_id == ^user_id and
            m.role in [:owner, :admin],
        select: true

    from p in Project,
      as: :project,
      where: p.organization_id == ^org_id,
      where:
        exists(org_privileged_query) or
          exists(
            from pm in ProjectMembership,
              where: pm.project_id == parent_as(:project).id and pm.user_id == ^user_id
          )
  end

  @spec with_member_count(Ecto.Query.t()) :: Ecto.Query.t()
  def with_member_count(query) do
    from p in query,
      left_join: pm in ProjectMembership,
      on: pm.project_id == p.id,
      group_by: p.id,
      select_merge: %{member_count: count(pm.id)}
  end
end
