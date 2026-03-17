defmodule Blackboex.Apis do
  @moduledoc """
  The Apis context. Manages API endpoints created by users.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.GenerationResult
  alias Blackboex.Repo

  @spec create_api(map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def create_api(attrs) do
    %Api{}
    |> Api.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_apis(Ecto.UUID.t()) :: [Api.t()]
  def list_apis(organization_id) do
    Api
    |> where([a], a.organization_id == ^organization_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @spec get_api(Ecto.UUID.t(), Ecto.UUID.t()) :: Api.t() | nil
  def get_api(organization_id, api_id) do
    Api
    |> where([a], a.organization_id == ^organization_id and a.id == ^api_id)
    |> Repo.one()
  end

  @spec update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def update_api(%Api{} = api, attrs) do
    api
    |> Api.changeset(attrs)
    |> Repo.update()
  end

  @spec create_api_from_generation(GenerationResult.t(), Ecto.UUID.t(), integer(), String.t()) ::
          {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def create_api_from_generation(%GenerationResult{} = result, organization_id, user_id, name) do
    create_api(%{
      name: name,
      description: result.description,
      source_code: result.code,
      template_type: to_string(result.template),
      method: result.method || "POST",
      organization_id: organization_id,
      user_id: user_id,
      example_request: result.example_request,
      example_response: result.example_response,
      param_schema: result.param_schema
    })
  end
end
