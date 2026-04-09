defmodule BlackboexWeb.FlowWebhookController do
  @moduledoc """
  Controller for processing flow webhook executions.
  Public endpoint — no authentication required.
  """

  use BlackboexWeb, :controller

  alias Blackboex.FlowExecutions
  alias Blackboex.FlowExecutor
  alias Blackboex.Flows

  require Logger

  @spec execute(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def execute(conn, %{"token" => token}) do
    flow = Flows.get_flow_by_token!(token)

    if flow.status != "active" do
      conn |> put_status(422) |> json(%{error: "flow is not active (status: #{flow.status})"})
    else
      input = conn.body_params || %{}
      execution_mode = get_execution_mode(flow)

      case execution_mode do
        "async" -> execute_async(conn, flow, input)
        _sync -> execute_sync(conn, flow, input)
      end
    end
  rescue
    Ecto.NoResultsError ->
      conn |> put_status(404) |> json(%{error: "not found"})
  end

  defp execute_sync(conn, flow, input) do
    case FlowExecutor.execute_sync(flow, input) do
      {:ok, %{output: output, execution_id: exec_id, duration_ms: dur}} ->
        conn
        |> put_status(200)
        |> json(%{output: output, execution_id: exec_id, duration_ms: dur})

      {:ok, %{halted: true, execution_id: exec_id}} ->
        conn
        |> put_status(200)
        |> json(%{
          status: "halted",
          execution_id: exec_id,
          resume_url: "/webhook/#{flow.webhook_token}/resume"
        })

      {:error, %{error: error_msg, execution_id: exec_id}} ->
        status =
          if String.starts_with?(error_msg, "Payload validation failed"), do: 422, else: 500

        conn |> put_status(status) |> json(%{error: error_msg, execution_id: exec_id})

      {:error, reason} ->
        Logger.warning("Flow sync execution failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "execution failed"})
    end
  end

  defp execute_async(conn, flow, input) do
    case FlowExecutor.execute_async(flow, input) do
      {:ok, %{execution_id: exec_id}} ->
        conn
        |> put_status(202)
        |> json(%{execution_id: exec_id, status_url: "/api/v1/executions/#{exec_id}"})

      {:error, reason} ->
        Logger.warning("Flow async execution failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "execution failed"})
    end
  end

  @spec resume(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resume(conn, %{"token" => token, "event_type" => event_type}) do
    case FlowExecutions.get_halted_execution_by_token(token, event_type) do
      nil ->
        conn |> put_status(404) |> json(%{error: "no halted execution found for this event"})

      execution ->
        payload = conn.body_params || %{}
        do_resume(conn, execution, payload)
    end
  end

  defp do_resume(conn, execution, payload) do
    case FlowExecutions.update_execution_status(execution, "running") do
      {:ok, updated} ->
        run_resumed_flow(conn, execution.flow, updated, payload)

      {:error, _} ->
        conn |> put_status(500) |> json(%{error: "failed to resume execution"})
    end
  end

  defp run_resumed_flow(conn, flow, execution, payload) do
    case FlowExecutor.run(flow, payload, execution.id) do
      {:ok, result} ->
        output = extract_output(result)
        fresh = FlowExecutions.get_execution(execution.id)
        duration_ms = compute_duration(fresh)
        FlowExecutions.complete_execution(fresh, wrap_for_db(output), duration_ms)

        conn
        |> put_status(200)
        |> json(%{output: output, execution_id: execution.id, duration_ms: duration_ms})

      {:halted, _} ->
        conn |> put_status(200) |> json(%{status: "halted", execution_id: execution.id})

      {:error, reason} ->
        error_msg = format_error(reason)
        fresh = FlowExecutions.get_execution(execution.id)
        FlowExecutions.fail_execution(fresh, error_msg)
        conn |> put_status(500) |> json(%{error: error_msg, execution_id: execution.id})
    end
  end

  defp extract_output(%{output: output}), do: output
  defp extract_output(result), do: result

  defp wrap_for_db(output) when is_map(output), do: output
  defp wrap_for_db(output), do: %{"value" => output}

  defp compute_duration(%{started_at: %DateTime{} = started_at}),
    do: DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

  defp compute_duration(%{inserted_at: %NaiveDateTime{} = inserted_at}),
    do: NaiveDateTime.diff(DateTime.to_naive(DateTime.utc_now()), inserted_at, :millisecond)

  defp compute_duration(_), do: 0

  defp format_error(%{errors: errors}) when is_list(errors),
    do: errors |> Enum.map(&format_error/1) |> Enum.join("; ")

  defp format_error(%{error: error}), do: format_error(error)
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp get_execution_mode(flow) do
    nodes = flow.definition["nodes"] || []
    start_node = Enum.find(nodes, fn n -> n["type"] == "start" end)
    (start_node && start_node["data"] && start_node["data"]["execution_mode"]) || "sync"
  end
end
