defmodule Blackboex.Policy.Checks do
  @moduledoc """
  Check functions for the authorization policy.

  Three check families:

  - `org_role/3` — checks org membership role, ignores project context.
    Use for objects that are org-scoped (organization, project creation,
    membership management, api_key).

  - `role/3` — checks org membership role, but only when NO project context
    is set on the scope. Provides backward compatibility for resources that
    existed before project hierarchy was introduced.

  - `project_role/3` — checks the effective project role (from explicit
    project membership or implicit via org owner/admin). Use for
    project-scoped resources (api, flow, etc.) when project context is set.
  """

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations.Organization

  @doc """
  Checks org membership role regardless of project context.
  """
  @spec org_role(Scope.t(), Organization.t(), atom()) :: boolean()
  def org_role(
        %Scope{membership: membership, organization: org},
        %Organization{id: obj_org_id},
        role
      ) do
    not is_nil(membership) and org.id == obj_org_id and membership.role == role
  end

  def org_role(_scope, _object, _role), do: false

  @doc """
  Checks org membership role only when no project context is set.

  When a project is present in the scope, this returns false, deferring
  authorization to `project_role/3`.
  """
  @spec role(Scope.t(), Organization.t(), atom()) :: boolean()
  def role(
        %Scope{project: nil, membership: membership, organization: org},
        %Organization{id: obj_org_id},
        role
      ) do
    not is_nil(membership) and org.id == obj_org_id and membership.role == role
  end

  def role(_scope, _object, _role), do: false

  @doc """
  Checks the effective project role against a minimum required role.

  Role hierarchy (highest to lowest): `:implicit_admin` > `:admin` > `:editor` > `:viewer`.

  Returns true when the scope's effective project role is at or above `min_role`,
  and the scope belongs to the same org as the object.
  """
  @spec project_role(Scope.t(), Organization.t(), atom()) :: boolean()
  def project_role(
        %Scope{membership: membership, organization: org} = scope,
        %Organization{id: obj_org_id},
        min_role
      ) do
    not is_nil(membership) and org.id == obj_org_id and
      has_project_role?(Scope.project_role(scope), min_role)
  end

  def project_role(_scope, _object, _role), do: false

  # Role hierarchy: implicit_admin satisfies all roles.
  defp has_project_role?(:implicit_admin, _min), do: true
  defp has_project_role?(:admin, min) when min in [:admin, :editor, :viewer], do: true
  defp has_project_role?(:editor, min) when min in [:editor, :viewer], do: true
  defp has_project_role?(:viewer, :viewer), do: true
  defp has_project_role?(_, _), do: false
end
