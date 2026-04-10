defmodule BlackboexWeb.Components.Editor.ChatPanel do
  @moduledoc """
  LiveComponent for the agent conversation timeline.
  Renders a compact, IDE-style timeline with collapsible tool steps,
  run summary at the end, and vertical timeline connector.
  """

  use BlackboexWeb, :live_component

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
        <h2 class="text-sm font-semibold flex items-center gap-1.5">
          <.icon name="hero-bolt" class="size-4 text-primary" /> Agent Timeline
        </h2>
        <button
          phx-click="request_confirm"
          phx-value-action="clear_conversation"
          class="text-xs text-muted-foreground hover:text-foreground"
        >
          New conversation
        </button>
      </div>

      <%!-- Scrollable timeline area --%>
      <div class="flex-1 min-h-0 overflow-y-auto" id="chat-messages" phx-hook="ChatAutoScroll">
        <%= if @grouped_events == [] and @pending_edit == nil and @streaming_tokens == "" and not @loading do %>
          <p class="text-sm text-muted-foreground text-center py-12 px-4">
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
                <div class="absolute -left-[9px] top-3 size-[13px] rounded-full border-2 border-info bg-background flex items-center justify-center animate-pulse">
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
                <span class="text-xs text-muted-foreground animate-pulse ml-2">Thinking...</span>
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
            <button
              type="button"
              phx-click="quick_action"
              phx-value-text={action}
              class="rounded-full border px-2 py-0.5 text-[11px] text-muted-foreground hover:bg-accent hover:text-accent-foreground"
            >
              {action}
            </button>
          <% end %>
        </div>
        <form phx-submit="send_chat" class="flex gap-2">
          <input
            type="text"
            name="chat_input"
            value={@input}
            placeholder="Describe the changes..."
            class="flex-1 rounded-md border bg-background px-3 py-2 text-sm"
            autocomplete="off"
            disabled={@loading}
          />
          <button
            type="submit"
            disabled={@loading}
            class="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Pending Edit ────────────────────────────────────────────────────────

  defp render_pending_edit(assigns) do
    ~H"""
    <div class="rounded-lg border border-info/30 bg-info/10 p-3 space-y-2.5">
      <div class="flex items-center gap-1.5">
        <.icon name="hero-pencil-square" class="size-4 text-info-foreground" />
        <span class="text-xs font-semibold text-info-foreground">Proposed Change</span>
      </div>
      <p class="text-xs text-info-foreground">{@pending_edit[:explanation] || ""}</p>

      <%= if @pending_edit[:files_changed] && @pending_edit[:files_changed] != [] do %>
        <div class="space-y-2">
          <%= for file <- @pending_edit.files_changed do %>
            <div class="rounded border bg-background p-1.5">
              <div class="text-[10px] font-semibold text-muted-foreground mb-1">{file.path}</div>
              <div class="text-[11px] font-mono overflow-x-auto max-h-40 overflow-y-auto">
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
          <div class="rounded border bg-background p-1.5 text-[11px] font-mono overflow-x-auto max-h-60 overflow-y-auto">
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
        <p class="text-[10px] text-muted-foreground italic">
          Validation will run after you accept.
        </p>
      <% end %>

      <%= if @pending_edit[:diff] do %>
        <p class="text-[10px] text-muted-foreground">{format_diff_summary(@pending_edit.diff)}</p>
      <% end %>

      <div class="flex gap-2">
        <button
          phx-click="accept_edit"
          class="rounded-md bg-success px-3 py-1 text-xs font-medium text-success-foreground hover:bg-success/90 flex items-center gap-1"
        >
          <.icon name="hero-check" class="size-3" /> Accept
        </button>
        <button
          phx-click="reject_edit"
          class="rounded-md border border-destructive/50 px-3 py-1 text-xs font-medium text-destructive hover:bg-destructive/10 flex items-center gap-1"
        >
          <.icon name="hero-x-mark" class="size-3" /> Reject
        </button>
      </div>
    </div>
    """
  end
end
