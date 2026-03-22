defmodule Blackboex.Docs.OpenApiGenerator do
  @moduledoc """
  Generates OpenAPI 3.1 specs as plain maps from API metadata.
  No external dependencies — produces JSON-serializable maps.
  """

  alias Blackboex.Apis.Api

  @spec generate(Api.t(), keyword()) :: map()
  def generate(%Api{} = api, opts \\ []) do
    base_url = Keyword.get(opts, :base_url)

    %{
      "openapi" => "3.1.0",
      "info" => build_info(api),
      "servers" => build_servers(base_url),
      "paths" => build_paths(api),
      "components" => build_components(api),
      "security" => build_security(api)
    }
  end

  @spec to_json(map()) :: String.t()
  def to_json(spec) do
    Jason.encode!(spec, pretty: true)
  end

  @spec to_yaml(map()) :: String.t()
  def to_yaml(spec) do
    Ymlr.document!(spec)
  end

  # --- Private ---

  defp build_info(%Api{name: name, description: desc}) do
    info = %{"title" => name, "version" => "1.0.0"}

    if desc do
      Map.put(info, "description", desc)
    else
      info
    end
  end

  defp build_servers(nil), do: []
  defp build_servers(base_url), do: [%{"url" => base_url}]

  defp build_paths(%Api{template_type: "computation"} = api) do
    %{
      "/" => %{
        "get" => build_operation(api, "get"),
        "post" => build_operation(api, "post")
      }
    }
  end

  defp build_paths(%Api{template_type: "crud"} = api) do
    %{
      "/" => %{
        "get" => build_list_operation(api),
        "post" => build_operation(api, "post")
      },
      "/{id}" => %{
        "get" => build_item_operation(api, "get"),
        "put" => build_item_operation(api, "put"),
        "delete" => build_item_operation(api, "delete")
      }
    }
  end

  defp build_paths(%Api{template_type: "webhook"} = api) do
    %{
      "/" => %{
        "post" => build_operation(api, "post")
      }
    }
  end

  defp build_operation(%Api{} = api, method) do
    op = %{
      "operationId" => "#{method}_#{api.slug}",
      "summary" => operation_summary(api, method),
      "responses" => build_responses(api)
    }

    if method in ["post", "put", "patch"] and has_body_schema?(api) do
      Map.put(op, "requestBody", build_request_body(api))
    else
      op
    end
  end

  defp build_list_operation(%Api{} = api) do
    %{
      "operationId" => "list_#{api.slug}",
      "summary" => "List #{api.name} resources",
      "responses" => %{
        "200" => %{
          "description" => "Successful response",
          "content" => %{
            "application/json" => %{
              "schema" => %{"type" => "array", "items" => %{"type" => "object"}}
            }
          }
        }
      }
    }
  end

  defp build_item_operation(%Api{} = api, method) do
    op = %{
      "operationId" => "#{method}_#{api.slug}_by_id",
      "summary" => item_summary(api, method),
      "parameters" => [id_parameter()],
      "responses" => build_responses(api)
    }

    if method == "put" and has_body_schema?(api) do
      Map.put(op, "requestBody", build_request_body(api))
    else
      op
    end
  end

  defp build_request_body(%Api{} = api) do
    schema = param_schema_to_json_schema(api.param_schema)

    content = %{"schema" => schema}

    content =
      if api.example_request do
        Map.put(content, "example", api.example_request)
      else
        content
      end

    %{
      "required" => true,
      "content" => %{"application/json" => content}
    }
  end

  defp build_responses(%Api{} = api) do
    response_content =
      if api.example_response do
        %{
          "application/json" => %{
            "schema" => %{"type" => "object"},
            "example" => api.example_response
          }
        }
      else
        %{"application/json" => %{"schema" => %{"type" => "object"}}}
      end

    %{
      "200" => %{
        "description" => "Successful response",
        "content" => response_content
      },
      "400" => %{"description" => "Bad request"},
      "500" => %{"description" => "Internal server error"}
    }
  end

  defp build_components(%Api{requires_auth: true}) do
    %{
      "securitySchemes" => %{
        "bearerAuth" => %{
          "type" => "http",
          "scheme" => "bearer",
          "description" => "API key for authentication. Use your bb_live_* key as the Bearer token."
        }
      }
    }
  end

  defp build_components(_api), do: %{}

  defp build_security(%Api{requires_auth: true}), do: [%{"bearerAuth" => []}]
  defp build_security(_api), do: []

  defp param_schema_to_json_schema(nil), do: %{"type" => "object"}

  defp param_schema_to_json_schema(param_schema) when is_map(param_schema) do
    properties =
      Map.new(param_schema, fn {field, type} ->
        {field, %{"type" => normalize_type(type)}}
      end)

    %{"type" => "object", "properties" => properties}
  end

  defp normalize_type("integer"), do: "integer"
  defp normalize_type("float"), do: "number"
  defp normalize_type("number"), do: "number"
  defp normalize_type("boolean"), do: "boolean"
  defp normalize_type("array"), do: "array"
  defp normalize_type("map"), do: "object"
  defp normalize_type("object"), do: "object"
  defp normalize_type(_), do: "string"

  defp has_body_schema?(%Api{param_schema: nil}), do: false
  defp has_body_schema?(%Api{param_schema: schema}) when map_size(schema) == 0, do: false
  defp has_body_schema?(_api), do: true

  defp operation_summary(%Api{name: name}, "get"), do: "Get #{name}"
  defp operation_summary(%Api{name: name}, "post"), do: "Execute #{name}"
  defp operation_summary(%Api{name: name}, method), do: "#{String.capitalize(method)} #{name}"

  defp item_summary(%Api{name: name}, "get"), do: "Get #{name} by ID"
  defp item_summary(%Api{name: name}, "put"), do: "Update #{name} by ID"
  defp item_summary(%Api{name: name}, "delete"), do: "Delete #{name} by ID"
  defp item_summary(%Api{name: name}, method), do: "#{String.capitalize(method)} #{name} by ID"

  defp id_parameter do
    %{
      "name" => "id",
      "in" => "path",
      "required" => true,
      "schema" => %{"type" => "string"}
    }
  end
end
