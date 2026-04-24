defmodule Blackboex.FlowExecutor.EnvResolver do
  @moduledoc """
  Resolves `{{env.NAME}}` (canonical) and `{{secrets.NAME}}` (legacy alias)
  placeholders in a flow definition map, fetching plaintext values from the
  project-scoped `Blackboex.ProjectEnvVars` context.

  Works with plain maps (BlackboexFlow definition format), not ParsedFlow
  structs — placeholder substitution happens AFTER validation but BEFORE
  parsing, so downstream node steps never see raw placeholders.

  ## Redaction

  `redact/2` replaces env values back with their `{{env.NAME}}` placeholder
  before persisting execution outputs. Only values with `byte_size >= 8`
  are considered for redaction so trivial values like `"1"`, `"true"`, or
  `"GET"` don't mangle unrelated output text. Real secrets (API keys,
  tokens, signatures) all comfortably clear that threshold.
  """

  alias Blackboex.ProjectEnvVars

  @env_pattern ~r/\{\{(?:env|secrets)\.([a-zA-Z0-9_]+)\}\}/

  # Minimum byte length for a value to be redacted. Values below this limit
  # (`"1"`, `"true"`, `"GET"`, short booleans / enums) would corrupt
  # unrelated output if we replaced them blindly. Real secrets are always
  # well above 8 bytes.
  @redact_min_length 8

  @doc """
  Walks all string values in a flow definition map, finds every match of
  `{{env.NAME}}` or `{{secrets.NAME}}`, and replaces them with the plaintext
  value stored in `ProjectEnvVars` under the given project.

  Returns `{:ok, resolved_definition}` when every referenced env var exists,
  or `{:error, {:missing_env, name}}` at the first missing name (fail-fast).
  """
  @spec resolve(map(), Ecto.UUID.t() | nil) ::
          {:ok, map()} | {:error, {:missing_env, String.t()}}
  def resolve(definition, project_id) do
    env_names = collect_env_names(definition)

    case fetch_env_values(env_names, project_id) do
      {:ok, env_map} -> {:ok, replace_env(definition, env_map)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Given a map of name→value pairs, replaces occurrences of those values back
  to `{{env.NAME}}` placeholders. Used before persisting execution results so
  plaintext env values never land in stored outputs.

  Values shorter than 8 bytes are **not** redacted — values like `"1"`,
  `"true"`, or `"GET"` collide with legitimate output fragments and their
  blanket replacement causes more confusion than it prevents. Secrets in
  practice always clear that threshold.
  """
  @spec redact(map(), %{optional(String.t()) => String.t()}) :: map()
  def redact(definition, env_values) do
    redactable =
      env_values
      |> Enum.filter(fn {_name, value} ->
        is_binary(value) and byte_size(value) >= @redact_min_length
      end)
      |> Map.new(fn {name, value} -> {value, name} end)

    deep_map_strings(definition, fn str -> redact_string(str, redactable) end)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp collect_env_names(definition) do
    definition
    |> collect_strings([])
    |> Enum.flat_map(fn str ->
      @env_pattern
      |> Regex.scan(str, capture: :all_but_first)
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

  defp fetch_env_values([], _project_id), do: {:ok, %{}}

  defp fetch_env_values(names, project_id) do
    runtime_map = ProjectEnvVars.load_runtime_map(project_id)

    Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, acc} ->
      case Map.fetch(runtime_map, name) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
        :error -> {:halt, {:error, {:missing_env, name}}}
      end
    end)
  end

  defp replace_env(definition, env_map) do
    deep_map_strings(definition, fn str ->
      Regex.replace(@env_pattern, str, fn _full, name ->
        Map.get(env_map, name, "{{env.#{name}}}")
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
      String.replace(acc, value, "{{env.#{name}}}")
    end)
  end
end
