defmodule Blackboex.LLM.ReqLLMClient do
  @moduledoc """
  Real LLM client implementation using ReqLLM.

  Delegates to `ReqLLM.generate_text/3` and `ReqLLM.stream_text/3`, threading
  the caller-supplied `:api_key` through ReqLLM's native per-request option.

  When `:api_key` is missing from opts the call short-circuits with
  `{:error, :missing_api_key}` — there is **no platform fallback**. Callers
  must resolve the project-scoped key via
  `Blackboex.LLM.Config.client_for_project/1` and forward the result.

  Common HTTP error statuses are normalized to stable atoms so the UI can
  surface actionable messages without parsing provider-specific envelopes.
  """

  @behaviour Blackboex.LLM.ClientBehaviour

  @impl true
  @spec generate_text(String.t(), keyword()) ::
          {:ok, %{content: String.t(), usage: map()}}
          | {:error, :missing_api_key | :invalid_api_key | :rate_limited | term()}
  def generate_text(prompt, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      model = Keyword.get(opts, :model, default_model())
      system = Keyword.get(opts, :system, "")

      context =
        ReqLLM.Context.new([
          ReqLLM.Context.system(system),
          ReqLLM.Context.user(prompt)
        ])

      req_opts = build_req_opts(opts, api_key)

      case ReqLLM.generate_text(model, context, req_opts) do
        {:ok, response} ->
          {:ok,
           %{
             content: ReqLLM.Response.text(response),
             usage: response.usage || %{}
           }}

        {:error, reason} ->
          {:error, map_error(reason)}
      end
    end
  end

  @impl true
  @spec stream_text(String.t(), keyword()) ::
          {:ok, Enumerable.t()}
          | {:error, :missing_api_key | :invalid_api_key | :rate_limited | term()}
  def stream_text(prompt, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      model = Keyword.get(opts, :model, default_model())
      system = Keyword.get(opts, :system, "")

      context =
        ReqLLM.Context.new([
          ReqLLM.Context.system(system),
          ReqLLM.Context.user(prompt)
        ])

      req_opts = build_req_opts(opts, api_key)

      case ReqLLM.stream_text(model, context, req_opts) do
        {:ok, stream_response} -> {:ok, stream_response}
        {:error, reason} -> {:error, map_error(reason)}
      end
    end
  end

  @spec resolve_api_key(keyword()) :: {:ok, String.t()} | {:error, :missing_api_key}
  defp resolve_api_key(opts) do
    case Keyword.get(opts, :api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  @spec build_req_opts(keyword(), String.t()) :: keyword()
  defp build_req_opts(opts, api_key) do
    opts
    |> Keyword.drop([:model, :system, :user_id, :api_key])
    |> Keyword.put_new(:temperature, 0.2)
    |> Keyword.put_new(:max_tokens, 8192)
    |> Keyword.put(:api_key, api_key)
  end

  @spec map_error(term()) :: :invalid_api_key | :rate_limited | term()
  defp map_error(%{status: 401}), do: :invalid_api_key
  defp map_error(%{status: 429}), do: :rate_limited
  defp map_error(%{"status" => 401}), do: :invalid_api_key
  defp map_error(%{"status" => 429}), do: :rate_limited
  defp map_error(%{reason: %{status: status}} = _err) when status == 401, do: :invalid_api_key
  defp map_error(%{reason: %{status: status}} = _err) when status == 429, do: :rate_limited
  defp map_error(other), do: other

  defp default_model do
    Application.get_env(:blackboex, :llm_default_model, "anthropic:claude-sonnet-4-20250514")
  end
end
