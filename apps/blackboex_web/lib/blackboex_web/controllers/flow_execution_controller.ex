defmodule BlackboexWeb.FlowExecutionController do
  @moduledoc """
  Controller for querying flow executions via API.
  Requires authenticated user with organization scope.
  """

  use BlackboexWeb, :controller

  alias Blackboex.FlowExecutions
  alias Blackboex.Flows

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    org = scope.organization

    case FlowExecutions.get_execution_for_org(org.id, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      execution ->
        conn |> put_status(200) |> json(BlackboexWeb.FlowExecutionJSON.show(execution))
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"slug" => slug}) do
    scope = conn.assigns.current_scope
    org = scope.organization

    case Flows.get_flow_by_slug(org.id, slug) do
      nil ->
        conn |> put_status(404) |> json(%{error: "flow not found"})

      flow ->
        executions = FlowExecutions.list_executions_for_flow(flow.id)
        conn |> put_status(200) |> json(BlackboexWeb.FlowExecutionJSON.index(executions))
    end
  end
end
