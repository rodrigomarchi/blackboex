defmodule Blackboex.Policy.Checks do
  @moduledoc """
  Check functions for the authorization policy.
  """

  alias Blackboex.Accounts.Scope
  alias Blackboex.Organizations.Organization

  @spec role(Scope.t(), Organization.t(), atom()) :: boolean()
  def role(%Scope{membership: membership, organization: org}, %Organization{id: obj_org_id}, role) do
    not is_nil(membership) and org.id == obj_org_id and membership.role == role
  end

  def role(_scope, _object, _role), do: false
end
