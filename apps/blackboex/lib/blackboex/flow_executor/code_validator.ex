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
    code_errors =
      case validate(data["code"]) do
        :ok -> []
        {:error, reason} -> [{id, "code", reason}]
      end

    undo_errors =
      case validate(data["undo_code"]) do
        :ok -> []
        {:error, reason} -> [{id, "undo_code", reason}]
      end

    code_errors ++ undo_errors ++ validate_skip_condition(data, id)
  end

  defp validate_node_code(%{id: id, type: :condition, data: data}) do
    case validate(data["expression"]) do
      :ok -> []
      {:error, reason} -> [{id, "expression", reason}]
    end
  end

  defp validate_node_code(%{id: id, type: :fail, data: data}) do
    message_errors =
      case validate(data["message"]) do
        :ok -> []
        {:error, reason} -> [{id, "message", reason}]
      end

    message_errors ++ validate_skip_condition(data, id)
  end

  defp validate_node_code(%{id: id, type: :for_each, data: data}) do
    source_errors =
      case validate(data["source_expression"]) do
        :ok -> []
        {:error, reason} -> [{id, "source_expression", reason}]
      end

    body_errors =
      case validate(data["body_code"]) do
        :ok -> []
        {:error, reason} -> [{id, "body_code", reason}]
      end

    source_errors ++ body_errors ++ validate_skip_condition(data, id)
  end

  defp validate_node_code(%{id: id, type: :sub_flow, data: data}) do
    mapping_errors =
      data
      |> Map.get("input_mapping", %{})
      |> validate_mapping_expressions(id)

    mapping_errors ++ validate_skip_condition(data, id)
  end

  defp validate_node_code(%{id: id, type: :debug, data: data}) do
    expression_errors =
      case validate(data["expression"]) do
        :ok -> []
        {:error, reason} -> [{id, "expression", reason}]
      end

    expression_errors ++ validate_skip_condition(data, id)
  end

  defp validate_node_code(%{id: id, type: type, data: data})
       when type in [:http_request, :delay, :webhook_wait] do
    validate_skip_condition(data, id)
  end

  defp validate_node_code(_node), do: []

  @spec validate_skip_condition(map(), String.t()) :: [{String.t(), String.t(), String.t()}]
  defp validate_skip_condition(data, id) do
    case Map.get(data, "skip_condition") do
      nil ->
        []

      "" ->
        []

      expr when is_binary(expr) ->
        case validate(expr) do
          :ok -> []
          {:error, reason} -> [{id, "skip_condition", reason}]
        end

      _ ->
        []
    end
  end

  @spec validate_mapping_expressions(map(), String.t()) :: [{String.t(), String.t(), String.t()}]
  defp validate_mapping_expressions(mapping, _id) when not is_map(mapping), do: []
  defp validate_mapping_expressions(mapping, _id) when map_size(mapping) == 0, do: []

  defp validate_mapping_expressions(mapping, id) do
    Enum.flat_map(mapping, fn {key, expression} ->
      case validate(expression) do
        :ok -> []
        {:error, reason} -> [{id, "input_mapping.#{key}", reason}]
      end
    end)
  end
end
