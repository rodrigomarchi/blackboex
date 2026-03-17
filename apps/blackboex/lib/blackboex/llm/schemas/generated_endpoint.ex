defmodule Blackboex.LLM.Schemas.GeneratedEndpoint do
  @moduledoc """
  Embedded schema for structured LLM responses representing a generated endpoint.
  Used with InstructorLite to validate LLM output.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :handler_code, :string
    field :method, :string
    field :description, :string
    field :example_request, :map
    field :example_response, :map
    field :param_schema, :map
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :handler_code,
      :method,
      :description,
      :example_request,
      :example_response,
      :param_schema
    ])
    |> validate_required([:handler_code, :method, :description])
  end
end
