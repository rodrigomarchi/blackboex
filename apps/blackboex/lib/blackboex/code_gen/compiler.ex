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
  def compile(%Api{} = api, source_code) do
    Tracer.with_span "blackboex.codegen.compile" do
      start_time = System.monotonic_time(:millisecond)
      module_name = module_name_for(api)
      template_type = String.to_atom(api.template_type)

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

    case issues do
      [] -> :ok
      errors -> {:error, {:validation, Enum.reverse(errors)}}
    end
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
      {:ok, [{^module_name, _binary}]} ->
        {:ok, module_name}

      {:error, error} ->
        errors = format_compile_errors(diagnostics, error)
        Logger.error("Compilation failed: #{errors}")
        {:error, {:compilation, errors}}
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
