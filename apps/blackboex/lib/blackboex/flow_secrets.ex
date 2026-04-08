defmodule Blackboex.FlowSecrets do
  @moduledoc """
  The FlowSecrets context. Manages encrypted secrets scoped to organizations,
  used by the flow execution engine.
  """

  alias Blackboex.FlowSecrets.FlowSecret
  alias Blackboex.FlowSecrets.FlowSecretQueries
  alias Blackboex.Repo

  @spec list_secrets(Ecto.UUID.t()) :: [FlowSecret.t()]
  def list_secrets(organization_id) do
    organization_id |> FlowSecretQueries.list_for_org() |> Repo.all()
  end

  @spec get_secret(Ecto.UUID.t(), String.t()) :: FlowSecret.t() | nil
  def get_secret(organization_id, name) do
    organization_id |> FlowSecretQueries.by_org_and_name(name) |> Repo.one()
  end

  @spec get_secret_value(Ecto.UUID.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_secret_value(organization_id, name) do
    case get_secret(organization_id, name) do
      nil -> {:error, :not_found}
      secret -> {:ok, FlowSecret.decrypt_value(secret.encrypted_value)}
    end
  end

  @spec create_secret(map()) :: {:ok, FlowSecret.t()} | {:error, Ecto.Changeset.t()}
  def create_secret(attrs) do
    %FlowSecret{}
    |> FlowSecret.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_secret(FlowSecret.t(), map()) ::
          {:ok, FlowSecret.t()} | {:error, Ecto.Changeset.t()}
  def update_secret(%FlowSecret{} = secret, attrs) do
    secret
    |> FlowSecret.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_secret(FlowSecret.t()) :: {:ok, FlowSecret.t()} | {:error, Ecto.Changeset.t()}
  def delete_secret(%FlowSecret{} = secret) do
    Repo.delete(secret)
  end
end
