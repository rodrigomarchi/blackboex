defmodule Blackboex.Apis.Keys do
  @moduledoc """
  Context for managing API keys. Keys are hashed with SHA-256
  and never stored in plain text.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiKey
  alias Blackboex.Repo

  @key_prefix "bb_live_"
  @hex_chars 32

  @spec create_key(Api.t(), map()) :: {:ok, String.t(), ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def create_key(%Api{} = api, attrs) do
    plain_key = generate_key()
    key_hash = hash_key(plain_key)
    key_prefix = String.slice(plain_key, 0, String.length(@key_prefix) + 8)

    changeset_attrs =
      Map.merge(attrs, %{
        api_id: api.id,
        key_hash: key_hash,
        key_prefix: key_prefix
      })

    case %ApiKey{}
         |> ApiKey.changeset(changeset_attrs)
         |> Repo.insert() do
      {:ok, api_key} -> {:ok, plain_key, api_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec verify_key(String.t()) :: {:ok, ApiKey.t()} | {:error, :invalid | :revoked | :expired}
  def verify_key(plain_key) do
    key_hash = hash_key(plain_key)

    # Query by prefix first for constant-time behavior: avoid timing leaks
    # that reveal whether a key exists, is revoked, or expired.
    prefix = String.slice(plain_key, 0, String.length(@key_prefix) + 8)

    case Repo.get_by(ApiKey, key_prefix: prefix) do
      nil ->
        {:error, :invalid}

      %ApiKey{} = api_key ->
        if Plug.Crypto.secure_compare(api_key.key_hash, key_hash) do
          check_key_status(api_key)
        else
          {:error, :invalid}
        end
    end
  end

  defp check_key_status(%ApiKey{revoked_at: revoked_at}) when not is_nil(revoked_at) do
    {:error, :revoked}
  end

  defp check_key_status(%ApiKey{expires_at: expires_at} = api_key) when not is_nil(expires_at) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
      {:error, :expired}
    else
      {:ok, api_key}
    end
  end

  defp check_key_status(%ApiKey{} = api_key), do: {:ok, api_key}

  @spec verify_key_for_api(String.t(), Ecto.UUID.t()) ::
          {:ok, ApiKey.t()} | {:error, :invalid | :revoked | :expired}
  def verify_key_for_api(plain_key, api_id) do
    case verify_key(plain_key) do
      {:ok, %ApiKey{api_id: ^api_id} = api_key} -> {:ok, api_key}
      {:ok, %ApiKey{}} -> {:error, :invalid}
      error -> error
    end
  end

  @spec list_keys(Ecto.UUID.t()) :: [ApiKey.t()]
  def list_keys(api_id) do
    ApiKey
    |> where([k], k.api_id == ^api_id)
    |> order_by([k], desc: k.inserted_at)
    |> Repo.all()
  end

  @spec revoke_key(ApiKey.t()) :: {:ok, ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def revoke_key(%ApiKey{} = api_key) do
    api_key
    |> ApiKey.changeset(%{revoked_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @spec rotate_key(ApiKey.t()) :: {:ok, String.t(), ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def rotate_key(%ApiKey{} = old_key) do
    old_key = Repo.preload(old_key, :api)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:revoke, ApiKey.changeset(old_key, %{revoked_at: DateTime.utc_now()}))
    |> Ecto.Multi.run(:new_key, fn _repo, _changes ->
      case create_key(old_key.api, %{
             label: old_key.label,
             organization_id: old_key.organization_id
           }) do
        {:ok, plain_key, api_key} -> {:ok, {plain_key, api_key}}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{new_key: {plain_key, api_key}}} -> {:ok, plain_key, api_key}
      {:error, :revoke, changeset, _} -> {:error, changeset}
      {:error, :new_key, changeset, _} -> {:error, changeset}
    end
  end

  @spec touch_last_used(ApiKey.t()) :: :ok
  def touch_last_used(%ApiKey{} = api_key) do
    # Only update if last update was more than 1 minute ago to avoid per-request writes
    threshold = DateTime.add(DateTime.utc_now(), -60)

    should_update =
      is_nil(api_key.last_used_at) or
        DateTime.compare(api_key.last_used_at, threshold) == :lt

    if should_update do
      ApiKey
      |> where([k], k.id == ^api_key.id)
      |> Repo.update_all(set: [last_used_at: DateTime.utc_now()])
    end

    :ok
  end

  defp generate_key do
    hex = :crypto.strong_rand_bytes(div(@hex_chars, 2)) |> Base.encode16(case: :lower)
    @key_prefix <> hex
  end

  defp hash_key(plain_key) do
    :crypto.hash(:sha256, plain_key)
  end
end
