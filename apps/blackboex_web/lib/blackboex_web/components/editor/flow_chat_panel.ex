defmodule BlackboexWeb.Components.Editor.FlowChatPanel do
  @moduledoc """
  Chat timeline + input for the Flow AI agent. Rendered inside the right-side
  drawer of `FlowLive.Edit`.

  Visually consistent with the Playground / Page chat panels — same message
  bubbles (`render_message_step/1`), same streaming code block
  (`render_streaming_code/1`), same input pill (`inline_input`), same
  `ChatAutoScroll` hook.

  Event contract (parent LiveView):

    * `phx-submit="send_chat"` on the form (value under `"message"`)
    * `phx-change="chat_input_change"` on the form
    * `phx-click="new_chat"` on the header "New conversation" button
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
  attr :current_stream_mode, :atom, default: nil
  attr :llm_configured?, :boolean, default: true
  attr :configure_url, :string, default: nil

  @spec flow_chat_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def flow_chat_panel(assigns) do
    assigns =
      Map.put(
        assigns,
        :timeline_empty,
        assigns.messages == [] and assigns.current_stream in [nil, ""] and not assigns.loading
      )

    ~H"""
    <.agent_chat_panel
      title="Flow Agent"
      icon="hero-sparkles"
      timeline_id="flow-chat-timeline"
      empty_description={"Ask the agent to create or edit the flow: \"approval flow with webhook_wait\", \"add an http_request\", \"connect the condition to the end node\"..."}
      timeline_empty={@timeline_empty}
      loading={@loading}
      llm_configured?={@llm_configured?}
      configure_url={@configure_url}
      input={@input}
      input_name="message"
      input_placeholder="Ask: generate an approval flow, add a delay, connect it to the webhook..."
      input_disabled={@loading}
      submit_disabled={@loading}
      new_conversation_disabled={@loading || @messages == []}
    >
      <:timeline>
        <.basic_timeline
          messages={@messages}
          loading={@loading}
          current_stream={@current_stream}
          current_stream_mode={@current_stream_mode}
        />
      </:timeline>
    </.agent_chat_panel>
    """
  end
end
