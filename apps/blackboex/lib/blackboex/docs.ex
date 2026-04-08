defmodule Blackboex.Docs do
  @moduledoc """
  The Docs context. Generates documentation and OpenAPI specs for APIs.
  """

  defdelegate generate(api, opts \\ []), to: Blackboex.Docs.DocGenerator

  defdelegate generate_openapi(api, opts \\ []),
    to: Blackboex.Docs.OpenApiGenerator,
    as: :generate

  defdelegate openapi_to_json(spec), to: Blackboex.Docs.OpenApiGenerator, as: :to_json
  defdelegate openapi_to_yaml(spec), to: Blackboex.Docs.OpenApiGenerator, as: :to_yaml
end
