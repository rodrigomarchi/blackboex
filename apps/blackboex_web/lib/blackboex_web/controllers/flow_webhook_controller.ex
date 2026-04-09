defmodule BlackboexWeb.FlowWebhookController do
  @moduledoc """
  Controller for processing flow webhook executions.
  Public endpoint — no authentication required.
  """

  use BlackboexWeb, :controller

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

  defp get_execution_mode(flow) do
    nodes = flow.definition["nodes"] || []
    start_node = Enum.find(nodes, fn n -> n["type"] == "start" end)
    (start_node && start_node["data"] && start_node["data"]["execution_mode"]) || "sync"
  end
end
