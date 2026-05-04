defmodule Blackboex.Organizations.OrganizationQueries do
  @moduledoc """
  Composable query builders for Organization and Membership schemas.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Organizations.{Membership, Organization}

  @spec for_user(integer()) :: Ecto.Query.t()
  def for_user(user_id) do
    Organization
    |> join(:inner, [o], m in Membership, on: m.organization_id == o.id)
    |> where([_o, m], m.user_id == ^user_id)
  end
end
