defmodule BlackboexWeb.Components.Editor.ChatPanel do
  @moduledoc """
  LiveComponent for the agent conversation timeline.
  Renders a compact, IDE-style timeline with collapsible tool steps,
  run summary at the end, and vertical timeline connector.
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.UI.AlertBanner

  import BlackboexWeb.Components.Editor.Chat.Panel,
    only: [agent_chat_panel: 1, streaming_step: 1, thinking_step: 1]

  import BlackboexWeb.Components.Editor.Chat.ChatMessage, only: [render_message_step: 1]

  import BlackboexWeb.Components.Editor.Chat.PipelineStatus,
    only: [
      render_run_summary: 1,
      render_tool_step: 1,
      render_standalone_result: 1,
      render_status_step: 1
    ]

  import BlackboexWeb.Components.Editor.ChatPanelHelpers,
    only: [
      group_events: 1,
      has_active_tool_call?: 1,
      quick_actions: 1,
      diff_line_class: 1,
      diff_prefix: 1,
      format_diff_summary: 1,
      test_summary: 1
    ]

  import BlackboexWeb.Components.Editor.ValidationDashboard, only: [validation_badge: 1]

  @impl true
  def render(assigns) do
    grouped_events = group_events(assigns.events)

    assigns =
      assigns
      |> assign(:grouped_events, grouped_events)
      |> assign(
        :timeline_empty,
        grouped_events == [] and assigns.pending_edit == nil and assigns.streaming_tokens == "" and
          not assigns.loading
      )

    ~H"""
    <div class="h-full">
      <.agent_chat_panel
        title="Agent Timeline"
        icon="hero-bolt"
        timeline_id="chat-messages"
        empty_description="Describe what you want the agent to build or change."
        timeline_empty={@timeline_empty}
        loading={@loading}
        input={@input}
        input_name="chat_input"
        input_placeholder="Describe the changes..."
        input_disabled={@loading}
        submit_disabled={@loading}
        change_event={nil}
        new_conversation_event="request_confirm"
        new_conversation_value_action="clear_conversation"
      >
        <:timeline>
          <%= if @grouped_events != [] or @loading or @streaming_tokens != "" or @run do %>
            <div class="relative ml-7 mr-4 my-3 border-l border-border pl-4">
              <%= for entry <- @grouped_events do %>
                <%= case entry do %>
                  <% {:message, event} -> %>
                    <.render_message_step event={event} />
                  <% {:tool_group, call, result} -> %>
                    <.render_tool_step call={call} result={result} streaming_tokens="" />
                  <% {:tool_call, call} -> %>
                    <.render_tool_step call={call} result={nil} streaming_tokens={@streaming_tokens} />
                  <% {:tool_result, result} -> %>
                    <.render_standalone_result result={result} />
                  <% {:status, event} -> %>
                    <.render_status_step event={event} />
                <% end %>
              <% end %>

              <.streaming_step
                :if={
                  @loading and not has_active_tool_call?(@grouped_events) and @streaming_tokens != ""
                }
                content={@streaming_tokens}
              />
              <.thinking_step
                :if={
                  @loading and not has_active_tool_call?(@grouped_events) and @streaming_tokens == ""
                }
                label="Thinking..."
              />

              <.render_run_summary :if={@run && !@loading} run={@run} />
            </div>
          <% end %>

          <div :if={@pending_edit} class="px-4 pb-4">
            <.render_pending_edit pending_edit={@pending_edit} />
          </div>
        </:timeline>

        <:composer_before>
          <div class="flex flex-wrap gap-1">
            <%= for action <- quick_actions(@template_type) do %>
              <.button
                type="button"
                variant="outline"
                size="pill"
                phx-click="quick_action"
                phx-value-text={action}
                class="text-2xs text-muted-foreground"
              >
                {action}
              </.button>
            <% end %>
          </div>
        </:composer_before>
      </.agent_chat_panel>
    </div>
    """
  end

  # ── Pending Edit ────────────────────────────────────────────────────────

  defp render_pending_edit(assigns) do
    ~H"""
    <.alert_banner variant="info" icon="hero-pencil-square">
      <div class="space-y-2.5">
        <span class="text-xs font-semibold text-info-foreground">Proposed Change</span>
        <p class="text-xs text-info-foreground">{@pending_edit[:explanation] || ""}</p>

        <%= if @pending_edit[:files_changed] && @pending_edit[:files_changed] != [] do %>
          <div class="space-y-2">
            <%= for file <- @pending_edit.files_changed do %>
              <div class="rounded border bg-background p-1.5">
                <div class="text-2xs font-semibold text-muted-foreground mb-1">{file.path}</div>
                <div class="text-2xs font-mono overflow-x-auto max-h-40 overflow-y-auto">
                  <%= for {op, lines} <- file.diff, line <- lines do %>
                    <div class={diff_line_class(op)}>
                      <span class="select-none text-muted-foreground mr-1">{diff_prefix(op)}</span>{line}
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <%= if @pending_edit[:diff] do %>
            <div class="rounded border bg-background p-1.5 text-2xs font-mono overflow-x-auto max-h-60 overflow-y-auto">
              <%= for {op, lines} <- @pending_edit.diff, line <- lines do %>
                <div class={diff_line_class(op)}>
                  <span class="select-none text-muted-foreground mr-1">{diff_prefix(op)}</span>{line}
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>

        <%= if @pending_edit[:validation] do %>
          <div class="flex flex-wrap gap-1">
            <.validation_badge check="Compile" status={@pending_edit.validation.compilation} />
            <.validation_badge check="Format" status={@pending_edit.validation.format} />
            <.validation_badge check="Credo" status={@pending_edit.validation.credo} />
            <.validation_badge
              check="Tests"
              status={@pending_edit.validation.tests}
              detail={test_summary(@pending_edit.validation.test_results)}
            />
          </div>
        <% else %>
          <p class="text-2xs text-muted-foreground italic">
            Validation will run after you accept.
          </p>
        <% end %>

        <%= if @pending_edit[:diff] do %>
          <p class="text-2xs text-muted-foreground">{format_diff_summary(@pending_edit.diff)}</p>
        <% end %>

        <div class="flex gap-2">
          <.button
            variant="success"
            size="compact"
            phx-click="accept_edit"
            class="flex items-center gap-1 font-medium"
          >
            <.icon name="hero-check" class="size-3" /> Accept
          </.button>
          <.button
            variant="outline-destructive"
            size="compact"
            phx-click="reject_edit"
            class="flex items-center gap-1 font-medium"
          >
            <.icon name="hero-x-mark" class="size-3" /> Reject
          </.button>
        </div>
      </div>
    </.alert_banner>
    """
  end
end
