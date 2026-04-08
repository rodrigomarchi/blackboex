defmodule Blackboex.Audit.AuditQueries do
  @moduledoc """
  Composable query builders for AuditLog schema.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Audit.AuditLog

  @spec for_organization(Ecto.UUID.t(), pos_integer()) :: Ecto.Query.t()
  def for_organization(organization_id, limit) do
    AuditLog
    |> where([a], a.organization_id == ^organization_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
  end

  @spec for_user(integer(), pos_integer()) :: Ecto.Query.t()
  def for_user(user_id, limit) do
    AuditLog
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
  end
end
