defmodule BlackboexWeb.Components.Editor.Chat.PipelineStatus do
  @moduledoc """
  Function components for rendering pipeline status indicators in the chat timeline:
  tool steps, run summary, status steps, and standalone results.
  """

  use BlackboexWeb, :html

  alias Phoenix.LiveView.JS

  import BlackboexWeb.Components.Editor.Chat.CodeBlocks,
    only: [render_code_block: 1, render_streaming_code: 1, render_tool_output: 1]

  import BlackboexWeb.Components.Shared.DashboardHelpers, only: [format_duration: 1]

  import BlackboexWeb.Components.Editor.ChatPanelHelpers,
    only: [
      tool_icon: 1,
      format_tool_display_name: 1,
      step_node_class: 1,
      compact_summary: 2,
      summary_color: 2,
      compute_step_duration: 2,
      format_timestamp: 1,
      format_tokens: 1,
      format_cost: 1,
      short_model: 1,
      run_type_icon: 1,
      run_type_label: 1
    ]

  @doc "Renders the run summary card at the end of the timeline."
  attr :run, :map, required: true

  def render_run_summary(assigns) do
    ~H"""
    <div class="relative pb-2 pt-1">
      <div class="timeline-dot top-[7px] border-muted-foreground/50">
        <.icon name="hero-chart-bar" class="size-2 text-accent-sky" />
      </div>
      <div class="rounded-md border bg-muted/20 px-3 py-2 ml-2 space-y-1.5">
        <%!-- Status row --%>
        <div class="flex items-center gap-2">
          <.icon name={run_type_icon(@run.run_type)} class="size-3.5 text-primary" />
          <span class="text-xs font-semibold">{run_type_label(@run.run_type)}</span>
          <.run_status_badge status={@run.status} />
          <span class="flex-1" />
          <%= if @run.model do %>
            <span class="text-2xs text-muted-foreground">{short_model(@run.model)}</span>
          <% end %>
        </div>
        <%!-- Timing --%>
        <div class="flex items-center gap-1 text-2xs text-muted-foreground">
          <.icon name="hero-clock" class="size-3 text-accent-amber" />
          <span>{format_timestamp(@run.started_at)}</span>
          <%= if @run.completed_at do %>
            <span>&rarr;</span>
            <span>{format_timestamp(@run.completed_at)}</span>
            <span class="text-foreground font-medium ml-1">
              {format_duration(@run.duration_ms)}
            </span>
          <% end %>
        </div>
        <%!-- Metrics row --%>
        <div class="flex items-center gap-3 text-2xs text-muted-foreground">
          <span class="flex items-center gap-0.5">
            <.icon name="hero-arrow-down-tray" class="size-2.5 text-accent-blue" />
            {format_tokens(@run.input_tokens)} in
          </span>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-arrow-up-tray" class="size-2.5 text-accent-emerald" />
            {format_tokens(@run.output_tokens)} out
          </span>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-currency-dollar" class="size-2.5 text-accent-amber" />
            {format_cost(@run.cost_cents)}
          </span>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-queue-list" class="size-2.5 text-accent-violet" />
            {to_string(@run.event_count || 0)} steps
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc "Renders a collapsible tool step in the timeline."
  attr :call, :map, required: true

  attr :result, :any,
    default: nil,
    doc: "map when complete, nil when the tool call is still active"

  attr :streaming_tokens, :string, default: ""

  def render_tool_step(assigns) do
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
      <div class={["timeline-dot top-[5px]", step_node_class(@result)]}>
        <.icon name={tool_icon(@call.tool)} class="size-[7px]" />
      </div>

      <%!-- Clickable collapsed header --%>
      <.button
        type="button"
        variant="ghost"
        class="h-auto w-full rounded-none px-0 py-0 text-left group ml-2 hover:bg-transparent"
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
              "text-2xs",
              summary_color(@call.tool, @result)
            ]}>
              {@summary}
            </span>
          <% end %>
          <span class="flex-1 border-b border-dotted border-muted-foreground/20 mx-1" />
          <span class="text-2xs text-muted-foreground font-mono">
            {if @result, do: @duration, else: "..."}
          </span>
        </div>
      </.button>

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
            <span class="text-muted-caption animate-pulse">Thinking...</span>
          </div>
        <% end %>

        <%!-- Timestamps --%>
        <div class="flex items-center gap-1 text-2xs text-muted-foreground">
          <.icon name="hero-clock" class="size-3 text-accent-amber" />
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

  @doc "Renders a standalone tool result (orphaned result without a matching call)."
  attr :result, :map, required: true

  def render_standalone_result(assigns) do
    ~H"""
    <div class="relative pb-1 pt-0.5">
      <div class={[
        "timeline-dot top-[5px]",
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

  @doc "Renders a status/info step in the timeline."
  attr :event, :map, required: true

  def render_status_step(assigns) do
    ~H"""
    <div class="relative py-1">
      <div class="timeline-dot-sm top-[9px] bg-muted-foreground/30" />
      <span class="text-2xs text-muted-foreground italic ml-2">{@event.content || ""}</span>
    </div>
    """
  end

  # Private sub-components

  defp run_status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-1.5 py-0.5 text-2xs font-medium",
      process_status_classes(@status)
    ]}>
      {@status}
    </span>
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
end
