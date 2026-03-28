defmodule Blackboex.Telemetry.Events do
  @moduledoc """
  Central telemetry event emission for BlackBoex domain operations.

  All custom telemetry events are emitted through this module, providing
  a single contract that both OpenTelemetry spans and PromEx plugins consume.

  Emissions are wrapped in try/rescue so a faulty telemetry handler
  never crashes the calling business logic.
  """

  require Logger

  @spec emit_api_request(map()) :: :ok
  def emit_api_request(metadata) do
    safe_execute(
      [:blackboex, :api, :request],
      %{duration: metadata.duration_ms},
      %{
        api_id: metadata.api_id,
        method: metadata.method,
        status: metadata.status_code
      }
    )
  end

  @spec emit_llm_call(map()) :: :ok
  def emit_llm_call(metadata) do
    safe_execute(
      [:blackboex, :llm, :call],
      %{
        duration: metadata.duration_ms,
        input_tokens: Map.get(metadata, :input_tokens, 0),
        output_tokens: Map.get(metadata, :output_tokens, 0)
      },
      %{
        provider: metadata.provider,
        model: metadata.model
      }
    )
  end

  @spec emit_codegen(map()) :: :ok
  def emit_codegen(metadata) do
    safe_execute(
      [:blackboex, :codegen, :generate],
      %{duration: metadata.duration_ms},
      %{
        template_type: metadata.template_type,
        description_length: metadata.description_length
      }
    )
  end

  @spec emit_compile(map()) :: :ok
  def emit_compile(metadata) do
    safe_execute(
      [:blackboex, :codegen, :compile],
      %{duration: metadata.duration_ms},
      %{
        api_id: metadata.api_id,
        success: metadata.success
      }
    )
  end

  @spec emit_sandbox_execute(map()) :: :ok
  def emit_sandbox_execute(metadata) do
    safe_execute(
      [:blackboex, :sandbox, :execute],
      %{duration: metadata.duration_ms},
      %{
        api_id: Map.get(metadata, :api_id)
      }
    )
  end

  @spec emit_agent_run(map()) :: :ok
  def emit_agent_run(metadata) do
    safe_execute(
      [:blackboex, :agent, :run],
      %{
        duration: Map.get(metadata, :duration_ms, 0),
        iteration_count: Map.get(metadata, :iteration_count, 0),
        cost_cents: Map.get(metadata, :cost_cents, 0)
      },
      %{
        run_id: metadata.run_id,
        run_type: metadata.run_type,
        status: metadata.status
      }
    )
  end

  @spec emit_agent_tool(map()) :: :ok
  def emit_agent_tool(metadata) do
    safe_execute(
      [:blackboex, :agent, :tool],
      %{duration: Map.get(metadata, :duration_ms, 0)},
      %{
        tool_name: metadata.tool_name,
        success: metadata.success,
        run_id: metadata.run_id
      }
    )
  end

  @spec emit_circuit_breaker(map()) :: :ok
  def emit_circuit_breaker(metadata) do
    safe_execute(
      [:blackboex, :circuit_breaker, :state_change],
      %{},
      %{
        provider: metadata.provider,
        from_state: metadata.from_state,
        to_state: metadata.to_state
      }
    )
  end

  @spec safe_execute([atom()], map(), map()) :: :ok
  defp safe_execute(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    error ->
      Logger.warning(
        "Telemetry emission failed for #{inspect(event)}: #{Exception.message(error)}"
      )

      :ok
  end
end
