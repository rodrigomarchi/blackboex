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

  import BlackboexWeb.Components.Editor.Chat.ChatMessage, only: [render_message_step: 1]
  import BlackboexWeb.Components.Editor.Chat.CodeBlocks, only: [render_streaming_code: 1]
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
  attr :llm_configured?, :boolean, default: true
  attr :configure_url, :string, default: nil

  @spec playground_chat_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def playground_chat_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center justify-between border-b px-4 py-2 shrink-0 bg-card">
        <.section_heading icon="hero-bolt" icon_class="size-4 text-primary">
          Playground Agent
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
        id="playground-chat-timeline"
        phx-hook="ChatAutoScroll"
      >
        <div :if={!@llm_configured?} class="px-3 pt-3">
          <.llm_not_configured_banner project_url={@configure_url} />
        </div>
        <%= if @messages == [] and @current_stream in [nil, ""] and not @loading do %>
          <p class="text-muted-description text-center py-12 px-4">
            Ask the agent to generate or edit this playground code.
          </p>
        <% else %>
          <%!-- Timeline with vertical line --%>
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

            <%!-- Streaming code block (while loading with tokens arriving) --%>
            <%= if @loading and is_binary(@current_stream) and @current_stream != "" do %>
              <div class="relative pb-2 pt-1">
                <div class="timeline-dot top-3 border-info animate-pulse">
                  <div class="size-[5px] rounded-full bg-info" />
                </div>
                <div class="ml-2">
                  <.render_streaming_code code={@current_stream} />
                </div>
              </div>
            <% end %>

            <%!-- Thinking indicator (loading but no tokens yet) --%>
            <%= if @loading and (is_nil(@current_stream) or @current_stream == "") do %>
              <div class="relative py-2">
                <div class="absolute -left-[7px] top-[11px] size-[9px] rounded-full bg-info animate-pulse" />
                <span class="text-muted-caption animate-pulse ml-2">Agent thinking...</span>
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Bottom spacer --%>
        <div class="h-4" />
      </div>

      <%!-- Input (pinned at bottom) --%>
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
            placeholder="Ask: generate a script, add IO.puts, refactor with pipe..."
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

  # render_message_step/1 expects an event-like map with :role, :content, :timestamp
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
