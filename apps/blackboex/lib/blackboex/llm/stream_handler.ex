defmodule Blackboex.LLM.StreamHandler do
  @moduledoc """
  Handles streaming LLM responses by spawning a Task that sends
  token events to a caller process (typically a LiveView).

  Events:
  - `{:llm_token, token}` — each streamed token
  - `{:llm_done, full_response}` — complete accumulated response
  - `{:llm_error, reason}` — error during streaming
  """

  alias Blackboex.LLM.Config

  @spec start(pid(), String.t(), keyword()) :: {:ok, pid()}
  def start(caller, prompt, opts) do
    Task.start(fn -> run_stream(caller, prompt, opts) end)
  end

  defp run_stream(caller, prompt, opts) do
    client = Config.client()

    case client.stream_text(prompt, opts) do
      {:ok, stream} ->
        full_response = consume_stream(caller, stream)
        send(caller, {:llm_done, full_response})

      {:error, reason} ->
        send(caller, {:llm_error, reason})
    end
  end

  defp consume_stream(caller, stream) do
    Enum.reduce(stream, "", fn {:token, token}, acc ->
      send(caller, {:llm_token, token})
      acc <> token
    end)
  end
end
