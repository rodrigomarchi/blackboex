defmodule Blackboex.FlowExecutor.CodeValidator do
  @moduledoc """
  Validates Elixir code syntax in flow nodes.
  """

  alias Blackboex.FlowExecutor.ParsedFlow

  @spec validate(String.t() | nil) :: :ok | {:error, String.t()}
  def validate(nil), do: :ok
  def validate(""), do: :ok

  def validate(code) when is_binary(code) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> :ok
      {:error, {_meta, message, token}} -> {:error, "#{message}#{token}"}
    end
  end

  @spec validate_flow(ParsedFlow.t()) :: :ok | {:error, [{String.t(), String.t(), String.t()}]}
  def validate_flow(%ParsedFlow{nodes: nodes}) do
    errors =
      nodes
      |> Enum.flat_map(&validate_node_code/1)

    case errors do
      [] -> :ok
      errs -> {:error, errs}
    end
  end

  @spec validate_node_code(Blackboex.FlowExecutor.ParsedNode.t()) ::
          [{String.t(), String.t(), String.t()}]
  defp validate_node_code(%{id: id, type: :elixir_code, data: data}) do
    case validate(data["code"]) do
      :ok -> []
      {:error, reason} -> [{id, "code", reason}]
    end
  end

  defp validate_node_code(%{id: id, type: :condition, data: data}) do
    case validate(data["expression"]) do
      :ok -> []
      {:error, reason} -> [{id, "expression", reason}]
    end
  end

  defp validate_node_code(_node), do: []
end
