defmodule Blackboex.Apis.ApiQueries do
  @moduledoc """
  Composable query builders for the Api schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api

  @spec list_for_org(Ecto.UUID.t()) :: Ecto.Query.t()
  def list_for_org(organization_id) do
    Api
    |> where([a], a.organization_id == ^organization_id)
    |> order_by([a], desc: a.inserted_at)
  end

  @spec by_org_and_id(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_org_and_id(organization_id, api_id) do
    Api
    |> where([a], a.organization_id == ^organization_id and a.id == ^api_id)
  end
end
