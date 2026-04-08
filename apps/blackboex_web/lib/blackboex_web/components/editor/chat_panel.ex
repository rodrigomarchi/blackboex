defmodule BlackboexWeb.Components.Editor.ChatPanel do
  @moduledoc """
  LiveComponent for the agent conversation timeline.
  Renders a compact, IDE-style timeline with collapsible tool steps,
  run summary at the end, and vertical timeline connector.
  """

  use BlackboexWeb, :live_component

  alias Blackboex.CodeGen.DiffEngine
  alias Phoenix.LiveView.JS

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
          phx-click="clear_conversation"
          class="text-xs text-muted-foreground hover:text-foreground"
          data-confirm="Clear conversation? Code will not be affected."
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

  # ── Run Summary (timeline item at the end) ─────────────────────────────

  defp render_run_summary(assigns) do
    ~H"""
    <div class="relative pb-2 pt-1">
      <div class="absolute -left-[9px] top-[7px] size-[13px] rounded-full border-2 bg-background flex items-center justify-center border-muted-foreground/50">
        <.icon name="hero-chart-bar" class="size-2" />
      </div>
      <div class="rounded-md border bg-muted/20 px-3 py-2 ml-2 space-y-1.5">
        <%!-- Status row --%>
        <div class="flex items-center gap-2">
          <.icon name={run_type_icon(@run.run_type)} class="size-3.5 text-primary" />
          <span class="text-xs font-semibold">{run_type_label(@run.run_type)}</span>
          <.run_status_badge status={@run.status} />
          <span class="flex-1" />
          <%= if @run.model do %>
            <span class="text-[10px] text-muted-foreground">{short_model(@run.model)}</span>
          <% end %>
        </div>
        <%!-- Timing --%>
        <div class="flex items-center gap-1 text-[10px] text-muted-foreground">
          <.icon name="hero-clock" class="size-3" />
          <span>{format_timestamp(@run.started_at)}</span>
          <%= if @run.completed_at do %>
            <span>&rarr;</span>
            <span>{format_timestamp(@run.completed_at)}</span>
            <span class="text-foreground font-medium ml-1">
              {format_duration_ms(@run.duration_ms)}
            </span>
          <% end %>
        </div>
        <%!-- Metrics row --%>
        <div class="flex items-center gap-3 text-[10px] text-muted-foreground">
          <span class="flex items-center gap-0.5">
            <.icon name="hero-arrow-down-tray" class="size-2.5" />
            {format_tokens(@run.input_tokens)} in
          </span>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-arrow-up-tray" class="size-2.5" />
            {format_tokens(@run.output_tokens)} out
          </span>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-currency-dollar" class="size-2.5" />
            {format_cost(@run.cost_cents)}
          </span>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-queue-list" class="size-2.5" />
            {to_string(@run.event_count || 0)} steps
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp run_status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-1.5 py-0.5 text-[10px] font-medium",
      status_badge_class(@status)
    ]}>
      {@status}
    </span>
    """
  end

  # ── Message Steps ───────────────────────────────────────────────────────

  defp render_message_step(assigns) do
    ~H"""
    <div class="relative pb-3 pt-1">
      <%!-- Timeline node on the border-l line --%>
      <div class={[
        "absolute -left-[7px] top-3 size-[9px] rounded-full border-2 bg-background",
        if(@event.role == "user", do: "border-primary", else: "border-muted-foreground/50")
      ]} />

      <div class={[
        "rounded-md px-3 py-2 text-sm ml-2",
        if(@event.role == "user",
          do: "bg-primary/10 border border-primary/20",
          else: "bg-muted/50"
        )
      ]}>
        <div class="flex items-center gap-1.5 mb-1">
          <.icon
            name={if(@event.role == "user", do: "hero-user", else: "hero-sparkles")}
            class="size-3 text-muted-foreground"
          />
          <span class="text-[10px] font-medium text-muted-foreground uppercase tracking-wider">
            {if @event.role == "user", do: "You", else: "Agent"}
          </span>
          <span class="flex-1" />
          <span class="text-[10px] text-muted-foreground">
            {format_timestamp(@event[:timestamp])}
          </span>
        </div>
        <p class="whitespace-pre-wrap text-xs leading-relaxed">{@event.content || ""}</p>
      </div>
    </div>
    """
  end

  # ── Tool Steps (collapsible) ────────────────────────────────────────────

  defp render_tool_step(assigns) do
    step_id =
      "step-#{assigns.call[:id] || :erlang.phash2({assigns.call.tool, assigns.call[:timestamp]})}"

    duration = compute_step_duration(assigns.call, assigns.result)
    summary = compact_summary(assigns.call.tool, assigns.result)

    assigns =
      assigns
      |> assign(:step_id, step_id)
      |> assign(:duration, duration)
      |> assign(:summary, summary)

    ~H"""
    <div class="relative pb-1 pt-0.5">
      <%!-- Timeline node --%>
      <div class={[
        "absolute -left-[9px] top-[5px] flex items-center justify-center size-[13px] rounded-full bg-background border-2",
        step_node_class(@result)
      ]}>
        <.icon name={tool_icon(@call.tool)} class="size-[7px]" />
      </div>

      <%!-- Clickable collapsed header --%>
      <button
        type="button"
        class="w-full text-left group ml-2"
        phx-click={
          JS.toggle(to: "##{@step_id}-detail")
          |> JS.toggle(to: "##{@step_id}-chev-r")
          |> JS.toggle(to: "##{@step_id}-chev-d")
        }
      >
        <div class="flex items-center gap-1.5 py-0.5">
          <span id={"#{@step_id}-chev-r"} class={if(is_nil(@result), do: "hidden", else: "")}>
            <.icon name="hero-chevron-right-mini" class="size-3 text-muted-foreground" />
          </span>
          <span id={"#{@step_id}-chev-d"} class={if(is_nil(@result), do: "", else: "hidden")}>
            <.icon name="hero-chevron-down-mini" class="size-3 text-muted-foreground" />
          </span>
          <span class="text-xs font-medium">{format_tool_display_name(@call.tool)}</span>
          <%= if @result do %>
            <.step_status_icon success={@result.success} />
          <% else %>
            <span class="size-3 rounded-full bg-info animate-pulse inline-block" />
          <% end %>
          <%= if @summary do %>
            <span class={[
              "text-[10px]",
              summary_color(@call.tool, @result)
            ]}>
              {@summary}
            </span>
          <% end %>
          <span class="flex-1 border-b border-dotted border-muted-foreground/20 mx-1" />
          <span class="text-[10px] text-muted-foreground font-mono">
            {if @result, do: @duration, else: "..."}
          </span>
        </div>
      </button>

      <%!-- Expandable detail panel — open when active, closed when complete --%>
      <div
        id={"#{@step_id}-detail"}
        class={[
          "mt-1.5 mb-2 ml-7 space-y-2",
          if(@result, do: "hidden", else: "")
        ]}
      >
        <%!-- Streaming tokens (inside active step) --%>
        <%= if is_nil(@result) and @streaming_tokens != "" do %>
          <.render_streaming_code code={@streaming_tokens} />
        <% end %>

        <%!-- Thinking inside active step (no tokens yet) --%>
        <%= if is_nil(@result) and @streaming_tokens == "" do %>
          <div class="py-1">
            <span class="text-xs text-muted-foreground animate-pulse">Thinking...</span>
          </div>
        <% end %>

        <%!-- Timestamps --%>
        <div class="flex items-center gap-1 text-[10px] text-muted-foreground">
          <.icon name="hero-clock" class="size-3" />
          <span>{format_timestamp(@call[:timestamp])}</span>
          <%= if @result && @result[:timestamp] do %>
            <span>&rarr;</span>
            <span>{format_timestamp(@result[:timestamp])}</span>
          <% end %>
        </div>

        <%!-- Input code --%>
        <%= if is_map(@call[:args]) and @call.args["code"] do %>
          <.render_code_block code={@call.args["code"]} label="Input" />
        <% end %>
        <%= if is_map(@call[:args]) and @call.args["test_code"] do %>
          <.render_code_block code={@call.args["test_code"]} label="Test Code" />
        <% end %>

        <%!-- Output --%>
        <%= if @result do %>
          <.render_tool_output
            tool={@result.tool}
            success={@result.success}
            content={@result.content}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp step_status_icon(assigns) do
    ~H"""
    <%= if @success do %>
      <.icon name="hero-check-circle" class="size-3.5 text-success-foreground" />
    <% else %>
      <.icon name="hero-x-circle" class="size-3.5 text-destructive" />
    <% end %>
    """
  end

  # ── Standalone tool result (orphaned) ───────────────────────────────────

  defp render_standalone_result(assigns) do
    ~H"""
    <div class="relative pb-1 pt-0.5">
      <div class={[
        "absolute -left-[9px] top-[5px] flex items-center justify-center size-[13px] rounded-full bg-background border-2",
        if(@result[:success], do: "border-success", else: "border-destructive")
      ]}>
        <.icon name={tool_icon(@result.tool)} class="size-[7px]" />
      </div>
      <div class="py-0.5 ml-2">
        <div class="flex items-center gap-1.5">
          <span class="text-xs font-medium">{format_tool_display_name(@result.tool)}</span>
          <.step_status_icon success={@result.success} />
        </div>
        <div class="mt-1">
          <.render_tool_output
            tool={@result.tool}
            success={@result.success}
            content={@result.content}
          />
        </div>
      </div>
    </div>
    """
  end

  # ── Status Steps ────────────────────────────────────────────────────────

  defp render_status_step(assigns) do
    ~H"""
    <div class="relative py-1">
      <div class="absolute -left-[5px] top-[9px] size-[5px] rounded-full bg-muted-foreground/30" />
      <span class="text-[10px] text-muted-foreground italic ml-2">{@event.content || ""}</span>
    </div>
    """
  end

  # ── Code Block with line numbers ────────────────────────────────────────

  defp render_code_block(assigns) do
    lines = String.split(assigns.code, "\n")
    line_count = length(lines)

    assigns =
      assigns
      |> assign(:line_count, line_count)
      |> assign(:lines, Enum.with_index(lines, 1))

    ~H"""
    <div class="rounded-md border bg-[#1e1e2e] overflow-hidden">
      <div class="flex items-center justify-between px-2.5 py-1 border-b border-white/10 bg-white/5">
        <span class="text-[10px] font-medium text-white/50 uppercase tracking-wider">
          {@label}
        </span>
        <span class="text-[10px] text-white/40">{@line_count} lines</span>
      </div>
      <div class="max-h-[300px] overflow-y-auto overflow-x-auto text-[11px] font-mono leading-snug">
        <%= for {line, num} <- @lines do %>
          <div class="flex hover:bg-white/5">
            <span class="select-none text-white/20 text-right w-8 pr-2 pl-2 shrink-0 border-r border-white/5">
              {num}
            </span>
            <span class="pl-3 pr-2 whitespace-pre highlight">{highlight_line(line)}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @makeup_mod Makeup
  @elixir_lexer Makeup.Lexers.ElixirLexer

  @spec highlight_line(String.t()) :: Phoenix.HTML.safe()
  defp highlight_line(line) do
    @makeup_mod.highlight_inner_html(line, lexer: @elixir_lexer)
    |> Phoenix.HTML.raw()
  rescue
    _ -> line
  end

  defp render_streaming_code(assigns) do
    lines = String.split(assigns.code, "\n")

    assigns =
      assigns
      |> assign(:lines, Enum.with_index(lines, 1))
      |> assign(:line_count, length(lines))

    ~H"""
    <div class="rounded-md border bg-[#1e1e2e] overflow-hidden">
      <div class="flex items-center justify-between px-2.5 py-1 border-b border-white/10 bg-white/5">
        <span class="text-[10px] font-medium text-white/50 uppercase tracking-wider">
          Streaming
        </span>
        <span class="inline-block w-1.5 h-3 bg-info animate-pulse rounded-sm" />
      </div>
      <div class="max-h-[300px] overflow-y-auto overflow-x-auto text-[11px] font-mono leading-snug">
        <%= for {line, num} <- @lines do %>
          <div class="flex hover:bg-white/5">
            <span class="select-none text-white/20 text-right w-8 pr-2 pl-2 shrink-0 border-r border-white/5">
              {num}
            </span>
            <span class="pl-3 pr-2 whitespace-pre highlight">{highlight_line(line)}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Tool Output (formatted per tool type) ───────────────────────────────

  defp render_tool_output(assigns) do
    assigns = assign(assigns, :is_code, looks_like_code?(assigns.content))

    ~H"""
    <%= if @content != "" do %>
      <%= if @is_code do %>
        <.render_code_block code={@content} label="Output" />
      <% else %>
        <div class={[
          "rounded-md border px-2.5 py-2 text-xs",
          if(!@success,
            do: "border-destructive bg-destructive/10",
            else: "bg-muted/30"
          )
        ]}>
          <div class="flex items-center gap-1 mb-1">
            <span class="text-[10px] font-medium text-muted-foreground uppercase tracking-wider">
              Output
            </span>
            <%= if !@success do %>
              <span class="text-[9px] rounded bg-destructive/10 text-destructive px-1 py-0.5 font-medium">
                ERROR
              </span>
            <% end %>
          </div>
          <pre class={[
            "whitespace-pre-wrap font-mono text-[11px] leading-relaxed max-h-[400px] overflow-y-auto",
            if(!@success, do: "text-destructive", else: "text-foreground")
          ]}><code>{@content}</code></pre>
        </div>
      <% end %>
    <% end %>
    """
  end

  @spec looks_like_code?(String.t() | nil) :: boolean()
  defp looks_like_code?(nil), do: false
  defp looks_like_code?(""), do: false

  defp looks_like_code?(content) when is_binary(content) do
    String.contains?(content, "defmodule") or
      String.contains?(content, "defp ") or
      (String.contains?(content, "def ") and String.contains?(content, "do"))
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

  # ── Event Grouping ──────────────────────────────────────────────────────

  @spec group_events(list(map())) :: list(tuple())
  defp group_events(events) when is_list(events) do
    events
    |> Enum.chunk_while(
      nil,
      fn
        %{type: :tool_call} = call, nil ->
          {:cont, call}

        %{type: :tool_result, tool: tool} = result, %{type: :tool_call, tool: tool} = call ->
          {:cont, {:tool_group, call, result}, nil}

        event, %{type: :tool_call} = pending_call ->
          {:cont, {:tool_call, pending_call}, event}

        event, nil ->
          {:cont, {event_tag(event), event}, nil}

        event, prev when is_map(prev) ->
          {:cont, {event_tag(prev), prev}, event}
      end,
      fn
        nil -> {:cont, nil}
        %{type: :tool_call} = call -> {:cont, {:tool_call, call}, nil}
        event when is_map(event) -> {:cont, {event_tag(event), event}, nil}
        _ -> {:cont, nil}
      end
    )
    |> Enum.reject(&is_nil/1)
  end

  defp group_events(_), do: []

  defp has_active_tool_call?(grouped_events) do
    Enum.any?(grouped_events, fn
      {:tool_call, _call} -> true
      _ -> false
    end)
  end

  defp event_tag(%{type: :message}), do: :message
  defp event_tag(%{type: :tool_call}), do: :tool_call
  defp event_tag(%{type: :tool_result}), do: :tool_result
  defp event_tag(%{type: :status}), do: :status
  defp event_tag(_), do: :status

  # ── Helpers ─────────────────────────────────────────────────────────────

  @spec tool_icon(String.t()) :: String.t()
  defp tool_icon("generate_code"), do: "hero-sparkles"
  defp tool_icon("compile_code"), do: "hero-cog-6-tooth"
  defp tool_icon("format_code"), do: "hero-paint-brush"
  defp tool_icon("lint_code"), do: "hero-magnifying-glass"
  defp tool_icon("generate_tests"), do: "hero-beaker"
  defp tool_icon("run_tests"), do: "hero-play"
  defp tool_icon("submit_code"), do: "hero-check-circle"
  defp tool_icon("generate_docs"), do: "hero-document-text"
  defp tool_icon("read_source"), do: "hero-document-text"
  defp tool_icon("edit_source"), do: "hero-pencil-square"
  defp tool_icon(_), do: "hero-wrench"

  @spec format_tool_display_name(String.t()) :: String.t()
  defp format_tool_display_name("generate_code"), do: "Generate Code"
  defp format_tool_display_name("compile_code"), do: "Compile"
  defp format_tool_display_name("format_code"), do: "Format"
  defp format_tool_display_name("lint_code"), do: "Lint"
  defp format_tool_display_name("generate_tests"), do: "Generate Tests"
  defp format_tool_display_name("run_tests"), do: "Run Tests"
  defp format_tool_display_name("submit_code"), do: "Submit"
  defp format_tool_display_name("generate_docs"), do: "Generate Docs"
  defp format_tool_display_name("read_source"), do: "Read Source"
  defp format_tool_display_name("edit_source"), do: "Edit Source"
  defp format_tool_display_name(name), do: name

  defp step_node_class(nil), do: "border-info animate-pulse"
  defp step_node_class(%{success: true}), do: "border-success"
  defp step_node_class(%{success: false}), do: "border-destructive"
  defp step_node_class(_), do: "border-muted-foreground/30"

  defp status_badge_class(status), do: process_status_classes(status)

  defp compact_summary(tool, nil) when tool in ~w(run_tests lint_code), do: nil

  defp compact_summary("lint_code", %{success: true, content: content}) do
    if String.contains?(content, "No issues"), do: nil, else: parse_lint_count(content)
  end

  defp compact_summary("run_tests", %{content: content}) do
    parse_test_count(content)
  end

  defp compact_summary(_, _), do: nil

  defp summary_color("lint_code", %{success: true}), do: "text-warning-foreground"
  defp summary_color("run_tests", %{success: true}), do: "text-success-foreground"
  defp summary_color("run_tests", %{success: false}), do: "text-destructive"
  defp summary_color(_, _), do: "text-muted-foreground"

  defp parse_lint_count(content) do
    case Regex.scan(~r/^\s*-\s/m, content) do
      [] -> nil
      matches -> "#{length(matches)} issues"
    end
  end

  defp parse_test_count(content) do
    cond do
      match = Regex.run(~r/(\d+) tests?,\s*(\d+) passed/, content) ->
        [_, total, passed] = match
        "#{passed}/#{total}"

      match = Regex.run(~r/(\d+) tests?.*?(\d+) failure/, content) ->
        [_, total, failed_count] = match
        passed = String.to_integer(total) - String.to_integer(failed_count)
        "#{passed}/#{total}"

      true ->
        nil
    end
  end

  defp compute_step_duration(call, nil) do
    format_duration_ms(call[:tool_duration_ms])
  end

  defp compute_step_duration(call, result) do
    cond do
      result[:tool_duration_ms] ->
        format_duration_ms(result[:tool_duration_ms])

      call[:timestamp] && result[:timestamp] ->
        format_duration(call[:timestamp], result[:timestamp])

      true ->
        ""
    end
  end

  @spec format_duration_ms(integer() | nil) :: String.t()
  defp format_duration_ms(nil), do: ""
  defp format_duration_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration_ms(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration_ms(ms), do: "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"

  defp format_duration(nil, _), do: ""
  defp format_duration(_, nil), do: ""

  defp format_duration(start_dt, end_dt) do
    diff_ms = DateTime.diff(end_dt, start_dt, :millisecond)
    format_duration_ms(max(diff_ms, 0))
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_timestamp(_), do: ""

  defp format_tokens(nil), do: "0"
  defp format_tokens(0), do: "0"
  defp format_tokens(n) when n < 1000, do: to_string(n)
  defp format_tokens(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_tokens(n), do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_cost(nil), do: "$0"
  defp format_cost(0), do: "$0"
  defp format_cost(cents), do: "$#{Float.round(cents / 100, 2)}"

  defp short_model(nil), do: ""

  defp short_model(model) do
    model
    |> String.replace(~r/^(claude-|gpt-)/, "")
    |> String.slice(0, 20)
  end

  defp run_type_icon("generation"), do: "hero-bolt"
  defp run_type_icon("edit"), do: "hero-pencil-square"
  defp run_type_icon("test_only"), do: "hero-beaker"
  defp run_type_icon("doc_only"), do: "hero-document-text"
  defp run_type_icon(_), do: "hero-bolt"

  defp run_type_label("generation"), do: "Generation"
  defp run_type_label("edit"), do: "Edit"
  defp run_type_label("test_only"), do: "Test Only"
  defp run_type_label("doc_only"), do: "Docs Only"
  defp run_type_label(_), do: "Run"

  defp diff_line_class(:ins), do: "bg-success/10 text-success-foreground"
  defp diff_line_class(:del), do: "bg-destructive/10 text-destructive"
  defp diff_line_class(:eq), do: ""

  defp diff_prefix(:ins), do: "+"
  defp diff_prefix(:del), do: "-"
  defp diff_prefix(:eq), do: " "

  defp format_diff_summary(diff), do: DiffEngine.format_diff_summary(diff)

  defp test_summary(test_results) when is_list(test_results) and test_results != [] do
    passed =
      Enum.count(test_results, fn
        %{"status" => "passed"} -> true
        %{status: "passed"} -> true
        _ -> false
      end)

    total = length(test_results)
    "#{passed}/#{total}"
  end

  defp test_summary(_), do: nil

  defp quick_actions("crud") do
    ["Add validation", "Add filter", "Add pagination", "Add error handling"]
  end

  defp quick_actions("webhook") do
    ["Add validation", "Validate signature", "Add error handling"]
  end

  defp quick_actions(_template_type) do
    ["Add validation", "Optimize performance", "Add error handling"]
  end
end
