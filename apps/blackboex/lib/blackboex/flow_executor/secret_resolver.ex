defmodule Blackboex.FlowExecutor.SecretResolver do
  @moduledoc """
  Resolves `{{secrets.NAME}}` placeholders in flow definition maps by fetching
  actual secret values from the database.

  Works with plain maps (BlackboexFlow definition format), not ParsedFlow structs.
  """

  alias Blackboex.FlowSecrets

  @secret_pattern ~r/\{\{secrets\.([a-zA-Z0-9_]+)\}\}/

  @doc """
  Walks all node data in a flow definition map, finds strings matching
  `{{secrets.NAME}}` pattern, and replaces them with actual values from DB.

  Returns `{:ok, updated_definition}` or `{:error, {:missing_secret, name}}`.
  """
  @spec resolve(map(), Ecto.UUID.t()) :: {:ok, map()} | {:error, {:missing_secret, String.t()}}
  def resolve(definition, org_id) do
    secret_names = collect_secret_names(definition)

    case fetch_secrets(secret_names, org_id) do
      {:ok, secret_map} -> {:ok, replace_secrets(definition, secret_map)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Given a map of name→value pairs, replaces occurrences of those values back
  to `{{secrets.NAME}}` placeholders. Used before persisting execution results.
  """
  @spec redact(map(), map()) :: map()
  def redact(definition, secret_values) do
    reverse_map = Map.new(secret_values, fn {name, value} -> {value, name} end)
    deep_map_strings(definition, fn str -> redact_string(str, reverse_map) end)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp collect_secret_names(definition) do
    definition
    |> collect_strings([])
    |> Enum.flat_map(fn str ->
      Regex.scan(@secret_pattern, str, capture: :all_but_first)
      |> List.flatten()
    end)
    |> Enum.uniq()
  end

  defp collect_strings(value, acc) when is_binary(value), do: [value | acc]

  defp collect_strings(value, acc) when is_map(value) do
    Enum.reduce(value, acc, fn {_k, v}, a -> collect_strings(v, a) end)
  end

  defp collect_strings(value, acc) when is_list(value) do
    Enum.reduce(value, acc, fn item, a -> collect_strings(item, a) end)
  end

  defp collect_strings(_value, acc), do: acc

  defp fetch_secrets([], _org_id), do: {:ok, %{}}

  defp fetch_secrets(names, org_id) do
    Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, acc} ->
      case FlowSecrets.get_secret_value(org_id, name) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
        {:error, :not_found} -> {:halt, {:error, {:missing_secret, name}}}
      end
    end)
  end

  defp replace_secrets(definition, secret_map) do
    deep_map_strings(definition, fn str ->
      Regex.replace(@secret_pattern, str, fn _full, name ->
        Map.get(secret_map, name, "{{secrets.#{name}}}")
      end)
    end)
  end

  defp deep_map_strings(value, fun) when is_binary(value), do: fun.(value)

  defp deep_map_strings(value, fun) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, deep_map_strings(v, fun)} end)
  end

  defp deep_map_strings(value, fun) when is_list(value) do
    Enum.map(value, fn item -> deep_map_strings(item, fun) end)
  end

  defp deep_map_strings(value, _fun), do: value

  defp redact_string(str, reverse_map) do
    Enum.reduce(reverse_map, str, fn {value, name}, acc ->
      String.replace(acc, value, "{{secrets.#{name}}}")
    end)
  end
end
