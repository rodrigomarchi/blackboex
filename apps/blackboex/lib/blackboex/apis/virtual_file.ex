defmodule Blackboex.Apis.VirtualFile do
  @moduledoc """
  Generates virtual (derived, read-only) file entries from Api fields.

  Virtual files appear in the file tree alongside real ApiFile records
  but are not stored in the database. They are generated on-the-fly
  from data already present on the Api schema.
  """

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.OpenApiGenerator

  @spec build(Api.t()) :: [map()]
  def build(%Api{} = api) do
    [build_openapi(api)]
    |> maybe_add(build_param_schema(api))
    |> maybe_add(build_example_request(api))
    |> maybe_add(build_example_response(api))
    |> maybe_add(build_validation_report(api))
  end

  defp build_openapi(api) do
    content = api |> OpenApiGenerator.generate() |> OpenApiGenerator.to_json()

    %{
      id: "virtual-openapi",
      path: "/docs/openapi.json",
      content: content,
      file_type: "generated",
      read_only: true
    }
  end

  defp build_param_schema(%Api{param_schema: ps}) when is_map(ps) and map_size(ps) > 0 do
    %{
      id: "virtual-param-schema",
      path: "/docs/param_schema.json",
      content: Jason.encode!(ps, pretty: true),
      file_type: "generated",
      read_only: true
    }
  end

  defp build_param_schema(_api), do: nil

  defp build_example_request(%Api{example_request: er}) when is_map(er) and map_size(er) > 0 do
    %{
      id: "virtual-example-request",
      path: "/docs/examples/request.json",
      content: Jason.encode!(er, pretty: true),
      file_type: "generated",
      read_only: true
    }
  end

  defp build_example_request(_api), do: nil

  defp build_example_response(%Api{example_response: er}) when is_map(er) and map_size(er) > 0 do
    %{
      id: "virtual-example-response",
      path: "/docs/examples/response.json",
      content: Jason.encode!(er, pretty: true),
      file_type: "generated",
      read_only: true
    }
  end

  defp build_example_response(_api), do: nil

  defp build_validation_report(%Api{validation_report: vr})
       when is_map(vr) and map_size(vr) > 0 do
    %{
      id: "virtual-validation-report",
      path: "/docs/validation_report.json",
      content: Jason.encode!(vr, pretty: true),
      file_type: "generated",
      read_only: true
    }
  end

  defp build_validation_report(_api), do: nil

  defp maybe_add(list, nil), do: list
  defp maybe_add(list, item), do: list ++ [item]
end
