defmodule BlackboexWeb.Components.Editor.ChatPanel do
  @moduledoc """
  LiveComponent for the agent conversation timeline.
  Renders a compact, IDE-style timeline with collapsible tool steps,
  run summary at the end, and vertical timeline connector.
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.SectionHeading

  import BlackboexWeb.Components.Editor.Chat.ChatMessage, only: [render_message_step: 1]

  import BlackboexWeb.Components.Editor.Chat.PipelineStatus,
    only: [
      render_run_summary: 1,
      render_tool_step: 1,
      render_standalone_result: 1,
      render_status_step: 1
    ]

  import BlackboexWeb.Components.Editor.Chat.CodeBlocks, only: [render_streaming_code: 1]

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
    assigns = assign(assigns, :grouped_events, group_events(assigns.events))

    ~H"""
    <div class="flex flex-col h-full overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center justify-between border-b px-4 py-2 shrink-0 bg-card">
        <.section_heading icon="hero-bolt" icon_class="size-4 text-primary">
          Agent Timeline
        </.section_heading>
        <.button
          variant="ghost-muted"
          size="compact"
          phx-click="request_confirm"
          phx-value-action="clear_conversation"
          class="px-0"
        >
          New conversation
        </.button>
      </div>

      <%!-- Scrollable timeline area --%>
      <div class="flex-1 min-h-0 overflow-y-auto" id="chat-messages" phx-hook="ChatAutoScroll">
        <%= if @grouped_events == [] and @pending_edit == nil and @streaming_tokens == "" and not @loading do %>
          <p class="text-muted-description text-center py-12 px-4">
            Describe what you want the agent to build or change.
          </p>
        <% else %>
          <%!-- Timeline with vertical line --%>
          <div class="relative ml-7 mr-4 my-3 pl-4 border-l border-border">
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

            <%!-- Streaming tokens fallback (when streaming before first tool step) --%>
            <%= if @loading and not has_active_tool_call?(@grouped_events) and @streaming_tokens != "" do %>
              <div class="relative pb-2 pt-1">
                <div class="timeline-dot top-3 border-info animate-pulse">
                  <div class="size-[5px] rounded-full bg-info" />
                </div>
                <div class="ml-2">
                  <.render_streaming_code code={@streaming_tokens} />
                </div>
              </div>
            <% end %>

            <%!-- Thinking indicator (when loading but no active tool step and no tokens yet) --%>
            <%= if @loading and not has_active_tool_call?(@grouped_events) and @streaming_tokens == "" do %>
              <div class="relative py-2">
                <div class="absolute -left-[7px] top-[11px] size-[9px] rounded-full bg-info animate-pulse" />
                <span class="text-muted-caption animate-pulse ml-2">Thinking...</span>
              </div>
            <% end %>

            <%!-- Run summary (last item in timeline) --%>
            <%= if @run && !@loading do %>
              <.render_run_summary run={@run} />
            <% end %>
          </div>

          <%!-- Pending edit (outside timeline line, inside scroll) --%>
          <%= if @pending_edit do %>
            <div class="px-4 pb-4">
              <.render_pending_edit pending_edit={@pending_edit} />
            </div>
          <% end %>
        <% end %>

        <%!-- Bottom spacer --%>
        <div class="h-4" />
      </div>

      <%!-- Quick actions + input (pinned at bottom) --%>
      <div class="border-t p-3 space-y-2 shrink-0 bg-card">
        <div class="flex flex-wrap gap-1">
          <%= for action <- quick_actions(@template_type) do %>
            <.button
              type="button"
              variant="outline"
              size="pill"
              phx-click="quick_action"
              phx-value-text={action}
              class="text-micro text-muted-foreground"
            >
              {action}
            </.button>
          <% end %>
        </div>
        <.form for={%{}} as={:chat} phx-submit="send_chat" class="flex gap-2">
          <.inline_input
            name="chat_input"
            value={@input}
            placeholder="Describe the changes..."
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
                <div class="text-micro font-mono overflow-x-auto max-h-40 overflow-y-auto">
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
            <div class="rounded border bg-background p-1.5 text-micro font-mono overflow-x-auto max-h-60 overflow-y-auto">
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
