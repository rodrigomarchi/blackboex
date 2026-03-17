defmodule Blackboex.LLM.ReqLLMClient do
  @moduledoc """
  Real LLM client implementation using ReqLLM.
  Delegates to `ReqLLM.generate_text/3` and `ReqLLM.stream_text/3`.
  """

  @behaviour Blackboex.LLM.ClientBehaviour

  @impl true
  @spec generate_text(String.t(), keyword()) ::
          {:ok, %{content: String.t(), usage: map()}} | {:error, term()}
  def generate_text(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())
    system = Keyword.get(opts, :system, "")

    context =
      ReqLLM.Context.new([
        ReqLLM.Context.system(system),
        ReqLLM.Context.user(prompt)
      ])

    req_opts =
      opts
      |> Keyword.drop([:model, :system, :user_id])
      |> Keyword.put_new(:temperature, 0.2)
      |> Keyword.put_new(:max_tokens, 8192)

    case ReqLLM.generate_text(model, context, req_opts) do
      {:ok, response} ->
        {:ok,
         %{
           content: response.content,
           usage: Map.from_struct(response.usage)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec stream_text(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_text(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())
    system = Keyword.get(opts, :system, "")

    context =
      ReqLLM.Context.new([
        ReqLLM.Context.system(system),
        ReqLLM.Context.user(prompt)
      ])

    req_opts =
      opts
      |> Keyword.drop([:model, :system, :user_id])
      |> Keyword.put_new(:temperature, 0.2)
      |> Keyword.put_new(:max_tokens, 8192)

    case ReqLLM.stream_text(model, context, req_opts) do
      {:ok, stream_response} ->
        {:ok, stream_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_model do
    Application.get_env(:blackboex, :llm_default_model, "anthropic:claude-sonnet-4-20250514")
  end
end
