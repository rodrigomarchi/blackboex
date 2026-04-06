defmodule Blackboex.CodeGen.Compiler do
  @moduledoc """
  Compiles validated code into live Elixir modules.

  Pipeline: validate AST -> build module -> compile -> return module atom.
  Uses Module.create/3 to ensure the compiled code matches the validated AST.
  """

  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.ASTValidator
  alias Blackboex.CodeGen.ModuleBuilder
  alias Blackboex.Telemetry.Events

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @spec compile(Api.t(), String.t()) ::
          {:ok, module()} | {:error, {:validation, [String.t()]} | {:compilation, term()}}
  @valid_template_types %{
    "computation" => :computation,
    "crud" => :crud,
    "webhook" => :webhook
  }

  def compile(%Api{} = api, source_code) do
    Tracer.with_span "blackboex.codegen.compile" do
      start_time = System.monotonic_time(:millisecond)
      module_name = module_name_for(api)
      template_type = Map.fetch!(@valid_template_types, api.template_type)

      result =
        with :ok <- check_handler_style(source_code),
             {:ok, _ast} <- validate(source_code),
             {:ok, full_code} <-
               ModuleBuilder.build_module(module_name, source_code, template_type),
             {:ok, full_ast} <- validate_full(full_code),
             {:ok, module} <- do_compile(module_name, full_ast) do
          {:ok, module}
        end

      duration_ms = System.monotonic_time(:millisecond) - start_time
      success = match?({:ok, _}, result)

      Tracer.set_attributes([
        {"blackboex.api_id", api.id},
        {"blackboex.success", success}
      ])

      Events.emit_compile(%{
        duration_ms: duration_ms,
        api_id: api.id,
        success: success
      })

      result
    end
  end

  @spec unload(module()) :: :ok
  def unload(module) when is_atom(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end

  @spec module_name_for(Api.t()) :: atom()
  def module_name_for(%Api{id: id}) do
    safe_id = String.replace(id, "-", "_")
    Module.concat([Blackboex.DynamicApi, "Api_#{safe_id}"])
  end

  # These module names are always allowed; additional modules are allowed
  # if they use Blackboex.Schema (nested embedded schemas for embeds_one/embeds_many)
  @allowed_dto_modules ~w(Request Response Params)

  defp check_handler_style(source_code) do
    issues =
      []
      |> check_pattern(
        source_code,
        ~r/\bjson\s*\(/,
        "uses json() — handler must return a plain map, not call json(conn, ...)"
      )
      |> check_pattern(
        source_code,
        ~r/\bput_status\s*\(/,
        "uses put_status() — handler must return a plain map, the framework handles HTTP status"
      )
      |> check_pattern(
        source_code,
        ~r/\bsend_resp\s*\(/,
        "uses send_resp() — handler must return a plain map, not send responses directly"
      )
      |> check_pattern(
        source_code,
        ~r/\bconn\b/,
        "references conn — handler must be a pure function receiving params and returning a map"
      )
      |> check_defmodule(source_code)

    case issues do
      [] -> :ok
      errors -> {:error, {:validation, Enum.reverse(errors)}}
    end
  end

  defp check_defmodule(acc, source_code) do
    # Extract module names that use Blackboex.Schema (nested embedded schemas)
    schema_modules = extract_schema_modules(source_code)

    # Find all defmodule occurrences and check that they are allowed
    Regex.scan(~r/\bdefmodule\s+(\w+)\b/, source_code)
    |> Enum.reduce(acc, fn [_full, name], issues ->
      if name in @allowed_dto_modules or name in schema_modules do
        issues
      else
        [
          "defines disallowed module #{name} — only Request, Response, Params, and Blackboex.Schema modules are allowed"
          | issues
        ]
      end
    end)
  end

  defp extract_schema_modules(source_code) do
    # Match: defmodule Name do ... use Blackboex.Schema
    ~r/\bdefmodule\s+(\w+)\b[\s\S]*?use\s+Blackboex\.Schema/
    |> Regex.scan(source_code)
    |> Enum.map(fn [_full, name] -> name end)
  end

  defp check_pattern(acc, code, pattern, message) do
    if Regex.match?(pattern, code), do: [message | acc], else: acc
  end

  defp validate(source_code) do
    case ASTValidator.validate(source_code) do
      {:ok, ast} -> {:ok, ast}
      {:error, reasons} -> {:error, {:validation, reasons}}
    end
  end

  defp validate_full(full_code) do
    # Parse the full module code — we skip the full AST security walk here
    # because the handler was already validated above and the template is trusted.
    case Code.string_to_quoted(full_code) do
      {:ok, ast} -> {:ok, ast}
      {:error, {_meta, msg, token}} -> {:error, {:compilation, "#{msg}#{token}"}}
    end
  end

  defp do_compile(module_name, ast) do
    # Purge old version if it exists (hot reload)
    :code.purge(module_name)
    :code.delete(module_name)

    # Capture compiler diagnostics for better error messages
    {result, diagnostics} = capture_diagnostics(fn -> Code.compile_quoted(ast) end)

    case result do
      {:ok, compiled_modules} when is_list(compiled_modules) ->
        verify_module_compiled(compiled_modules, module_name)

      {:error, error} ->
        errors = format_compile_errors(diagnostics, error)
        Logger.debug("Compilation failed: #{errors}")
        {:error, {:compilation, errors}}
    end
  end

  defp verify_module_compiled(compiled_modules, module_name) do
    if Enum.any?(compiled_modules, fn {mod, _} -> mod == module_name end) do
      {:ok, module_name}
    else
      {:error, {:compilation, "Main module #{inspect(module_name)} not found in compiled output"}}
    end
  end

  defp capture_diagnostics(fun) do
    Code.with_diagnostics(fn ->
      try do
        {:ok, fun.()}
      rescue
        error -> {:error, error}
      end
    end)
  end

  defp format_compile_errors(diagnostics, error) do
    diag_messages =
      diagnostics
      |> Enum.filter(&(&1.severity in [:error, :warning]))
      |> Enum.map(& &1.message)

    case diag_messages do
      [] -> Exception.message(error)
      msgs -> Enum.join(msgs, "; ")
    end
  end
end
