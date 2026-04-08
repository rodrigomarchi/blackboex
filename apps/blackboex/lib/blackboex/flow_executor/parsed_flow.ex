defmodule Blackboex.FlowExecutor.ParsedNode do
  @moduledoc """
  A parsed node from a BlackboexFlow definition.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: atom(),
          position: %{x: number(), y: number()},
          data: map()
        }

  @enforce_keys [:id, :type, :position]
  defstruct [:id, :type, :position, data: %{}]
end

defmodule Blackboex.FlowExecutor.ParsedFlow do
  @moduledoc """
  The result of parsing a BlackboexFlow JSON definition into a structured
  representation suitable for execution planning.
  """

  alias Blackboex.FlowExecutor.ParsedNode

  @type edge :: %{
          id: String.t(),
          source: String.t(),
          source_port: non_neg_integer(),
          target: String.t(),
          target_port: non_neg_integer()
        }

  @type t :: %__MODULE__{
          nodes: [ParsedNode.t()],
          edges: [edge()],
          start_node: ParsedNode.t(),
          end_node_ids: [String.t()],
          adjacency: %{String.t() => [String.t()]}
        }

  @enforce_keys [:start_node]
  defstruct [:start_node, nodes: [], edges: [], end_node_ids: [], adjacency: %{}]
end
