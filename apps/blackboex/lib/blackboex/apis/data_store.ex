defmodule Blackboex.Apis.DataStore do
  @moduledoc """
  Data store for CRUD APIs. Provides key-value storage scoped by api_id
  using JSONB in PostgreSQL.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.DataStore.Entry
  alias Blackboex.Repo

  @spec put(Ecto.UUID.t(), String.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def put(api_id, key, value) do
    %Entry{}
    |> Entry.changeset(%{api_id: api_id, key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
      conflict_target: [:api_id, :key],
      returning: true
    )
  end

  @spec get(Ecto.UUID.t(), String.t()) :: Entry.t() | nil
  def get(api_id, key) do
    get_entry(api_id, key)
  end

  @spec list(Ecto.UUID.t()) :: [Entry.t()]
  def list(api_id) do
    Entry
    |> where([e], e.api_id == ^api_id)
    |> order_by([e], asc: e.key)
    |> Repo.all()
  end

  @spec delete(Ecto.UUID.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(api_id, key) do
    case get_entry(api_id, key) do
      nil -> {:error, :not_found}
      entry -> Repo.delete(entry) |> then(fn {:ok, _} -> :ok end)
    end
  end

  defp get_entry(api_id, key) do
    Entry
    |> where([e], e.api_id == ^api_id and e.key == ^key)
    |> Repo.one()
  end
end
