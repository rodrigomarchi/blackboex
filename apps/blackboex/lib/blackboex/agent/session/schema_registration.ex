defmodule Blackboex.Agent.Session.SchemaRegistration do
  @moduledoc """
  Handles module compilation, registry registration, and OpenAPI schema extraction for Agent.Session.
  """

  require Logger

  alias Blackboex.Apis
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.Organizations

  @spec register_and_extract_schema(String.t(), String.t()) :: :ok
  def register_and_extract_schema(api_id, org_id) do
    api = Apis.get_api(org_id, api_id)
    do_register_module(api, org_id)
  rescue
    e ->
      Logger.error(
        "Failed to register module for API #{api_id}: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      :ok
  end

  @spec do_register_module(Blackboex.Apis.Api.t() | nil, String.t()) :: :ok
  def do_register_module(nil, _org_id), do: :ok

  def do_register_module(api, org_id) do
    source_files = Apis.get_source_for_compilation(api.id)

    if source_files == [] do
      :ok
    else
      compile_and_register(api, source_files, org_id)
    end
  end

  @spec compile_and_register(Blackboex.Apis.Api.t(), [map()], String.t()) :: :ok
  def compile_and_register(api, source_files, org_id) do
    case Compiler.compile_files(api, source_files) do
      {:ok, module} ->
        org = Organizations.get_organization(org_id)
        org_slug = if(org, do: org.slug, else: "")
        Apis.Registry.register(api.id, module, org_slug: org_slug, slug: api.slug)
        schema_attrs = extract_schema_attrs(module)
        Apis.update_api(api, Map.merge(%{status: "compiled"}, schema_attrs))
        :ok

      {:error, reason} ->
        Logger.warning("Failed to compile for registry: #{inspect(reason)}")
        :ok
    end
  end

  @spec extract_schema_attrs(module()) :: map()
  def extract_schema_attrs(module) do
    alias Blackboex.CodeGen.SchemaExtractor

    case SchemaExtractor.extract(module) do
      {:ok, %{request: req, response: resp} = schema} ->
        %{
          param_schema: SchemaExtractor.to_param_schema(schema),
          example_request: if(req, do: SchemaExtractor.generate_example(req), else: nil),
          example_response: if(resp, do: SchemaExtractor.generate_example(resp), else: nil)
        }

      {:error, _} ->
        %{}
    end
  rescue
    e ->
      Logger.warning("Schema extraction failed: #{Exception.message(e)}")
      %{}
  end
end
