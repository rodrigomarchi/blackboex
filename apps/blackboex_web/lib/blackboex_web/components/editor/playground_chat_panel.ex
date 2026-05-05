defmodule BlackboexWeb.Components.Editor.PlaygroundChatPanel do
  @moduledoc """
  Chat timeline + input for the Playground AI agent. Rendered inside the
  bottom panel (alongside the "Output" tab) of `PlaygroundLive.Edit`.

  Visually consistent with the API `ChatPanel` — same header section, same
  message bubbles (`render_message_step/1`), same streaming code block
  (`render_streaming_code/1`), same input pill (`inline_input`) — so the
  playground chat looks and feels like the rest of the editor UI.

  Event contract (parent LiveView):
    * `phx-submit="send_chat"` on the form (value under `"message"`)
    * `phx-change="chat_input_change"` on the form
    * `phx-click="new_chat"` on the header button
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.Chat.Panel,
    only: [agent_chat_panel: 1, basic_timeline: 1]

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:run_id) => String.t() | nil,
          optional(:timestamp) => DateTime.t() | NaiveDateTime.t() | nil
        }

  attr :messages, :list, required: true
  attr :input, :string, default: ""
  attr :loading, :boolean, default: false
  attr :current_stream, :string, default: nil
  attr :llm_configured?, :boolean, default: true
  attr :configure_url, :string, default: nil

  @spec playground_chat_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def playground_chat_panel(assigns) do
    assigns =
      Map.put(
        assigns,
        :timeline_empty,
        assigns.messages == [] and assigns.current_stream in [nil, ""] and not assigns.loading
      )

    ~H"""
    <.agent_chat_panel
      title="Playground Agent"
      icon="hero-bolt"
      timeline_id="playground-chat-timeline"
      empty_description="Ask the agent to generate or edit this playground code."
      timeline_empty={@timeline_empty}
      loading={@loading}
      llm_configured?={@llm_configured?}
      configure_url={@configure_url}
      input={@input}
      input_name="message"
      input_placeholder="Ask: generate a script, add IO.puts, refactor with pipe..."
      input_disabled={@loading}
      submit_disabled={@loading}
      new_conversation_disabled={@loading || @messages == []}
    >
      <:timeline>
        <.basic_timeline
          messages={@messages}
          loading={@loading}
          current_stream={@current_stream}
          current_stream_mode={nil}
        />
      </:timeline>
    </.agent_chat_panel>
    """
  end
end
