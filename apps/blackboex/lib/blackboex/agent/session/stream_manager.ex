defmodule Blackboex.Agent.Session.StreamManager do
  @moduledoc """
  Manages streaming token callbacks and file content accumulation for Agent.Session.
  """

  require Logger

  alias Blackboex.Agent.Session.EventTranslator
  alias Blackboex.Apis

  @spec build_token_callback(String.t()) :: (String.t() -> :ok)
  def build_token_callback(run_id) do
    fn token ->
      buffer = Process.get(:stream_buffer, "")
      new_buffer = buffer <> token

      # Accumulate content for current file (used to save to DB on file_completed)
      accumulated = Process.get(:current_streaming_content, "")
      Process.put(:current_streaming_content, accumulated <> token)

      if String.length(new_buffer) >= 20 or String.contains?(token, "\n") do
        Process.put(:stream_buffer, "")
        current_path = Process.get(:current_streaming_file)

        Phoenix.PubSub.broadcast(
          Blackboex.PubSub,
          "run:#{run_id}",
          {:agent_streaming, %{delta: new_buffer, path: current_path}}
        )
      else
        Process.put(:stream_buffer, new_buffer)
      end

      :ok
    end
  end

  @spec flush_remaining_stream(String.t()) :: :ok
  def flush_remaining_stream(run_id) do
    buffer = Process.get(:stream_buffer, "")

    if buffer != "" do
      Process.put(:stream_buffer, "")
      current_path = Process.get(:current_streaming_file)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "run:#{run_id}",
        {:agent_streaming, %{delta: buffer, path: current_path}}
      )
    end

    :ok
  end

  @spec build_broadcast_fn(Blackboex.Agent.Session.t()) :: (term() -> :ok)
  def build_broadcast_fn(state) do
    run_id = state.run_id
    conversation_id = state.conversation_id
    api_id = state.api_id
    organization_id = state.organization_id

    fn event ->
      EventTranslator.translate_pipeline_event(
        event,
        run_id,
        conversation_id,
        api_id,
        organization_id
      )
    end
  end

  @spec save_accumulated_file_content(String.t(), String.t()) :: :ok
  def save_accumulated_file_content(api_id, org_id) do
    prev_path = Process.get(:current_streaming_file)
    prev_content = Process.get(:current_streaming_content, "")

    Logger.debug(
      "SAVE_ACCUMULATED path=#{inspect(prev_path)} content_len=#{String.length(prev_content)}"
    )

    if prev_path && prev_content != "" do
      save_file_content_to_db(api_id, org_id, prev_path, prev_content)
    end

    :ok
  end

  @spec save_file_content_to_db(String.t(), String.t(), String.t(), String.t()) :: :ok
  def save_file_content_to_db(api_id, org_id, path, content) do
    api = Apis.get_api(org_id, api_id)

    if api do
      clean_content =
        case Regex.run(~r/```(?:elixir)?\s*\n(.*?)```/s, content) do
          [_, code] -> String.trim(code)
          nil -> String.trim(content)
        end

      case Apis.get_file(api.id, path) do
        nil ->
          Apis.create_file(api, %{path: path, content: clean_content, file_type: "source"})

        file ->
          Apis.update_file_content(file, clean_content, %{source: "generation"})
      end
    end

    :ok
  end

  @spec create_manifest_placeholders(String.t(), String.t(), [map()]) :: :ok
  def create_manifest_placeholders(api_id, org_id, manifest_files) do
    api = Apis.get_api(org_id, api_id)

    if api do
      existing_paths =
        api.id
        |> Apis.list_files()
        |> MapSet.new(& &1.path)

      for file <- manifest_files,
          path = file["path"],
          is_binary(path),
          not MapSet.member?(existing_paths, path) do
        Apis.create_file(api, %{
          path: path,
          content: "# Generating...\n",
          file_type: "source"
        })
      end
    end

    :ok
  end
end
