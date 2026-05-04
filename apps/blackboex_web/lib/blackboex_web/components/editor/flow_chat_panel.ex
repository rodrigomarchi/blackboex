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

  import BlackboexWeb.Components.Editor.Chat.ChatMessage, only: [render_message_step: 1]
  import BlackboexWeb.Components.Editor.Chat.CodeBlocks, only: [render_streaming_code: 1]
  import BlackboexWeb.Components.Editor.ChatPanelHelpers, only: [render_markdown: 1]
  import BlackboexWeb.Components.Shared.LlmNotConfiguredBanner
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.SectionHeading

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
    ~H"""
    <div class="flex flex-col h-full overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center justify-between border-b px-4 py-2 shrink-0 bg-card">
        <.section_heading icon="hero-sparkles" icon_class="size-4 text-primary">
          Flow Agent
        </.section_heading>
        <.button
          variant="ghost-muted"
          size="compact"
          phx-click="new_chat"
          disabled={@loading || @messages == []}
          class="px-0"
        >
          New conversation
        </.button>
      </div>

      <%!-- Scrollable timeline area --%>
      <div
        class="flex-1 min-h-0 overflow-y-auto"
        id="flow-chat-timeline"
        phx-hook="ChatAutoScroll"
      >
        <div :if={!@llm_configured?} class="px-3 pt-3">
          <.llm_not_configured_banner project_url={@configure_url} />
        </div>
        <%= if @messages == [] and @current_stream in [nil, ""] and not @loading do %>
          <p class="text-muted-description text-center py-12 px-4">
            Ask the agent to create or edit the flow: "approval flow with webhook_wait",
            "add an http_request", "connect the condition to the end node"...
          </p>
        <% else %>
          <div class="relative ml-7 mr-4 my-3 pl-4 border-l border-border">
            <%= for msg <- @messages do %>
              <%= case msg.role do %>
                <% role when role in ["user", "assistant"] -> %>
                  <.render_message_step event={message_to_event(msg)} />
                <% "system" -> %>
                  <.render_system_step content={msg.content} />
                <% _ -> %>
              <% end %>
            <% end %>

            <%= if @loading and is_binary(@current_stream) and @current_stream != "" do %>
              <div class="relative pb-2 pt-1">
                <div class="timeline-dot top-3 border-info animate-pulse">
                  <div class="size-[5px] rounded-full bg-info" />
                </div>
                <div class="ml-2">
                  <%= if @current_stream_mode == :explain do %>
                    <div class="rounded-md px-3 py-2 text-xs ml-0 bg-muted/50">
                      <div class="chat-markdown text-xs leading-relaxed">
                        {Phoenix.HTML.raw(render_markdown(@current_stream))}
                      </div>
                    </div>
                  <% else %>
                    <.render_streaming_code code={@current_stream} />
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @loading and (is_nil(@current_stream) or @current_stream == "") do %>
              <div class="relative py-2">
                <div class="absolute -left-[7px] top-[11px] size-[9px] rounded-full bg-info animate-pulse" />
                <span class="text-muted-caption animate-pulse ml-2">Agent thinking...</span>
              </div>
            <% end %>
          </div>
        <% end %>

        <div class="h-4" />
      </div>

      <%!-- Input --%>
      <div class="border-t p-3 shrink-0 bg-card">
        <.form
          for={%{}}
          as={:chat}
          phx-submit="send_chat"
          phx-change="chat_input_change"
          class="flex gap-2"
        >
          <.inline_input
            name="message"
            value={@input}
            placeholder="Ask: generate an approval flow, add a delay, connect it to the webhook..."
            class="flex-1 rounded-md"
            autocomplete="off"
            disabled={@loading}
          />
          <.button
            type="submit"
            variant="primary"
            disabled={@loading}
            class="rounded-md"
          >
            Send
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  defp message_to_event(msg) do
    %{
      role: msg.role,
      content: msg.content,
      timestamp: Map.get(msg, :timestamp)
    }
  end

  attr :content, :string, required: true

  defp render_system_step(assigns) do
    ~H"""
    <div class="relative pb-3 pt-1">
      <div class="timeline-dot-sm top-3 border-warning" />
      <div class="rounded-md px-3 py-2 text-xs ml-2 bg-warning/10 border border-warning/20 text-warning-foreground">
        {@content}
      </div>
    </div>
    """
  end
end
