defmodule BlackboexWeb.Components.Editor.Chat.Panel do
  @moduledoc """
  Canonical visual shell and common timeline pieces for agent chat panels.

  Agent-specific modules should stay as thin adapters around these components so
  Page, Playground, Flow, API, and Project chats share the same visual grammar.
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Editor.Chat.ChatMessage, only: [render_message_step: 1]
  import BlackboexWeb.Components.Editor.Chat.CodeBlocks, only: [render_streaming_code: 1]
  import BlackboexWeb.Components.Editor.ChatPanelHelpers, only: [render_markdown: 1]
  import BlackboexWeb.Components.Shared.EmptyState
  import BlackboexWeb.Components.Shared.LlmNotConfiguredBanner
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.SectionHeading

  attr :title, :string, required: true
  attr :icon, :string, default: "hero-sparkles"
  attr :timeline_id, :string, required: true
  attr :empty_description, :string, required: true
  attr :timeline_empty, :boolean, default: true
  attr :loading, :boolean, default: false
  attr :llm_configured?, :boolean, default: true
  attr :configure_url, :string, default: nil
  attr :input, :string, default: ""
  attr :input_name, :string, default: "message"
  attr :input_placeholder, :string, default: "Describe the change..."
  attr :input_disabled, :boolean, default: false
  attr :submit_disabled, :boolean, default: false
  attr :submit_event, :string, default: "send_chat"
  attr :change_event, :any, default: "chat_input_change"
  attr :show_new_conversation?, :boolean, default: true
  attr :new_conversation_event, :string, default: "new_chat"
  attr :new_conversation_value_action, :string, default: nil
  attr :new_conversation_disabled, :boolean, default: false
  attr :new_conversation_label, :string, default: "New conversation"
  attr :class, :any, default: nil

  slot :composer_before
  slot :timeline

  @spec agent_chat_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def agent_chat_panel(assigns) do
    ~H"""
    <div
      data-component="agent-chat-panel"
      class={["flex h-full flex-col overflow-hidden bg-background", @class]}
    >
      <div class="flex shrink-0 items-center justify-between border-b bg-card px-4 py-2">
        <.section_heading icon={@icon} icon_class="size-4 text-primary" compact>
          {@title}
        </.section_heading>
        <.button
          :if={@show_new_conversation?}
          variant="ghost-muted"
          size="compact"
          phx-click={@new_conversation_event}
          phx-value-action={@new_conversation_value_action}
          disabled={@new_conversation_disabled}
          class="px-0"
        >
          {@new_conversation_label}
        </.button>
      </div>

      <div class="min-h-0 flex-1 overflow-y-auto" id={@timeline_id} phx-hook="ChatAutoScroll">
        <div :if={!@llm_configured?} class="px-3 pt-3">
          <.llm_not_configured_banner project_url={@configure_url} />
        </div>

        <%= if @timeline_empty and not @loading do %>
          <.empty_state
            compact
            title={@empty_description}
            class="px-4 py-12 text-muted-foreground"
          />
        <% else %>
          {render_slot(@timeline)}
        <% end %>

        <div class="h-4" />
      </div>

      <div class="shrink-0 space-y-2 border-t bg-card p-3">
        {render_slot(@composer_before)}
        <.form
          for={%{}}
          as={:chat}
          phx-submit={@submit_event}
          phx-change={@change_event}
          class="flex gap-2"
        >
          <.inline_input
            name={@input_name}
            value={@input}
            placeholder={@input_placeholder}
            class="flex-1 rounded-md"
            autocomplete="off"
            disabled={@input_disabled}
          />
          <.button
            type="submit"
            variant="primary"
            disabled={@submit_disabled}
            class="rounded-md"
          >
            Send
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false
  attr :current_stream, :string, default: nil
  attr :current_stream_mode, :atom, default: nil
  attr :thinking_label, :string, default: "Agent thinking..."

  @spec basic_timeline(map()) :: Phoenix.LiveView.Rendered.t()
  def basic_timeline(assigns) do
    assigns = Map.put(assigns, :streaming?, present?(assigns.current_stream))

    ~H"""
    <div
      data-component="agent-chat-timeline"
      class="relative ml-7 mr-4 my-3 border-l border-border pl-4"
    >
      <%= for msg <- @messages do %>
        <%= case message_role(msg) do %>
          <% role when role in ["user", "assistant"] -> %>
            <.message_step message={msg} />
          <% "system" -> %>
            <.system_step content={message_content(msg)} />
          <% _ -> %>
        <% end %>
      <% end %>

      <.streaming_step
        :if={@loading and @streaming?}
        content={@current_stream}
        mode={@current_stream_mode}
      />
      <.thinking_step :if={@loading and not @streaming?} label={@thinking_label} />
    </div>
    """
  end

  attr :message, :map, required: true

  @spec message_step(map()) :: Phoenix.LiveView.Rendered.t()
  def message_step(assigns) do
    assigns = assign(assigns, :event, message_to_event(assigns.message))

    ~H"""
    <.render_message_step event={@event} />
    """
  end

  attr :content, :string, required: true

  @spec system_step(map()) :: Phoenix.LiveView.Rendered.t()
  def system_step(assigns) do
    ~H"""
    <div class="relative pb-3 pt-1">
      <div class="timeline-dot-sm top-3 border-warning" />
      <.alert_banner variant="warning" class="ml-2 px-3 py-2 text-xs">
        {@content}
      </.alert_banner>
    </div>
    """
  end

  attr :content, :string, required: true
  attr :mode, :atom, default: nil

  @spec streaming_step(map()) :: Phoenix.LiveView.Rendered.t()
  def streaming_step(assigns) do
    ~H"""
    <div class="relative pb-2 pt-1">
      <div class="timeline-dot top-3 border-info animate-pulse">
        <div class="size-[5px] rounded-full bg-info" />
      </div>
      <div class="ml-2">
        <%= if @mode == :explain do %>
          <div class="rounded-md bg-muted/50 px-3 py-2 text-xs">
            <div class="chat-markdown text-xs leading-relaxed">
              {Phoenix.HTML.raw(render_markdown(@content || ""))}
            </div>
          </div>
        <% else %>
          <.render_streaming_code code={@content || ""} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :label, :string, default: "Agent thinking..."

  @spec thinking_step(map()) :: Phoenix.LiveView.Rendered.t()
  def thinking_step(assigns) do
    ~H"""
    <div class="relative py-2">
      <div class="absolute -left-[7px] top-[11px] size-[9px] rounded-full bg-info animate-pulse" />
      <span class="text-muted-caption ml-2 animate-pulse">{@label}</span>
    </div>
    """
  end

  defp message_to_event(message) do
    %{
      role: message_role(message),
      content: message_content(message),
      timestamp: Map.get(message, :timestamp) || Map.get(message, "timestamp")
    }
  end

  defp message_role(message), do: Map.get(message, :role) || Map.get(message, "role")

  defp message_content(message),
    do: Map.get(message, :content) || Map.get(message, "content") || ""

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false
end
