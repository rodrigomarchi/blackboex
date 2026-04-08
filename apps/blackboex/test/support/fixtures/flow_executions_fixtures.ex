defmodule Blackboex.FlowExecutionsFixtures do
  @moduledoc """
  Test helpers for creating FlowExecution and NodeExecution entities.
  """

  alias Blackboex.FlowExecutions

  @doc """
  Creates a flow execution.

  ## Options

    * `:flow` - the flow to execute (default: auto-created via flow_fixture)
    * `:input` - execution input (default: %{})
    * Any additional attrs are ignored (user/org used from flow)

  Returns the FlowExecution struct.
  """
  @spec flow_execution_fixture(map()) :: Blackboex.FlowExecutions.FlowExecution.t()
  def flow_execution_fixture(attrs \\ %{}) do
    flow = attrs[:flow] || Blackboex.FlowsFixtures.flow_fixture(Map.take(attrs, [:user, :org]))

    {:ok, execution} = FlowExecutions.create_execution(flow, attrs[:input] || %{})

    execution
  end

  @doc """
  Creates a node execution within a flow execution.

  ## Options

    * `:flow_execution` - the parent execution (default: auto-created)
    * `:node_id` - the node ID (default: "n1")
    * `:node_type` - the node type (default: "http_request")

  Returns the NodeExecution struct.
  """
  @spec node_execution_fixture(map()) :: Blackboex.FlowExecutions.NodeExecution.t()
  def node_execution_fixture(attrs \\ %{}) do
    execution =
      attrs[:flow_execution] || flow_execution_fixture(Map.take(attrs, [:user, :org, :flow]))

    {:ok, node_exec} =
      FlowExecutions.create_node_execution(%{
        flow_execution_id: execution.id,
        node_id: attrs[:node_id] || "n1",
        node_type: attrs[:node_type] || "http_request"
      })

    node_exec
  end
end
