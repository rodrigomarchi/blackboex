defmodule Blackboex.Projects.ProjectQueries do
  @moduledoc """
  Query builders for Projects. Only contains query builders -- no Repo calls.
  """
  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api
  alias Blackboex.Flows.Flow
  alias Blackboex.Organizations.Membership
  alias Blackboex.Pages.Page
  alias Blackboex.Playgrounds.Playground
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

  @doc """
  Returns all projects for an organization with resource counts in a single SQL query.

  Each row is a plain map:
  `%{project: Project.t(), pages_count: integer(), apis_count: integer(),
     flows_count: integer(), playgrounds_count: integer()}`

  Ordered by `project.name ASC`.
  """
  @spec list_with_counts(Blackboex.Organizations.Organization.t()) :: Ecto.Query.t()
  def list_with_counts(%{id: org_id}) do
    pages_q = from p in Page, where: p.project_id == parent_as(:proj).id, select: count()
    apis_q = from a in Api, where: a.project_id == parent_as(:proj).id, select: count()
    flows_q = from f in Flow, where: f.project_id == parent_as(:proj).id, select: count()

    playgrounds_q =
      from pg in Playground, where: pg.project_id == parent_as(:proj).id, select: count()

    from p in Project,
      as: :proj,
      where: p.organization_id == ^org_id,
      select: %{
        project: p,
        pages_count: subquery(pages_q),
        apis_count: subquery(apis_q),
        flows_count: subquery(flows_q),
        playgrounds_count: subquery(playgrounds_q)
      },
      order_by: [asc: p.name]
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
