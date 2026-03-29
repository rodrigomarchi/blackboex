defmodule BlackboexWeb.Components.ChatPanel do
  @moduledoc """
  LiveComponent for the agent conversation timeline.
  Renders a chronological event list with user/assistant messages,
  tool call/result cards, status changes, streaming output, and pending edits.
  """

  use BlackboexWeb, :live_component

  alias Blackboex.Apis.DiffEngine

  import BlackboexWeb.Components.ValidationDashboard, only: [validation_badge: 1]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :grouped_events, group_events(assigns.events))

    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center justify-between border-b px-4 py-2">
        <h2 class="text-sm font-semibold">Agent Timeline</h2>
        <button
          phx-click="clear_conversation"
          class="text-xs text-muted-foreground hover:text-foreground"
          data-confirm="Clear conversation? Code will not be affected."
        >
          New conversation
        </button>
      </div>

      <div
        class="flex-1 overflow-y-auto p-4 space-y-4"
        id="chat-messages"
      >
        <%= if @grouped_events == [] and @pending_edit == nil and @streaming_tokens == "" and not @loading do %>
          <p class="text-sm text-muted-foreground text-center py-12">
            Describe what you want the agent to build or change.
          </p>
        <% else %>
          <%= for entry <- @grouped_events do %>
            <%= case entry do %>
              <% {:message, event} -> %>
                <.render_message event={event} />
              <% {:tool_group, call, result} -> %>
                <.render_tool_group call={call} result={result} />
              <% {:tool_call, call} -> %>
                <.render_tool_group call={call} result={nil} />
              <% {:tool_result, result} -> %>
                <.render_standalone_tool_result result={result} />
              <% {:status, event} -> %>
                <.render_status event={event} />
            <% end %>
          <% end %>
        <% end %>

        <%!-- Streaming tokens --%>
        <%= if @loading && @streaming_tokens != "" do %>
          <div class="flex justify-start">
            <div class="max-w-full rounded-lg bg-muted px-4 py-3 text-sm">
              <pre class="whitespace-pre-wrap font-mono text-xs"><code>{@streaming_tokens}</code></pre>
              <span class="inline-block w-1.5 h-4 bg-primary animate-pulse ml-0.5" />
            </div>
          </div>
        <% end %>

        <%!-- Loading / Thinking --%>
        <%= if @loading && @streaming_tokens == "" do %>
          <div class="flex justify-start">
            <div class="bg-muted rounded-lg px-4 py-3 text-sm text-muted-foreground animate-pulse">
              Thinking...
            </div>
          </div>
        <% end %>

        <%!-- Pending edit with Accept/Reject --%>
        <%= if @pending_edit do %>
          <div class="rounded-lg border border-blue-200 bg-blue-50 dark:border-blue-800 dark:bg-blue-950 p-4 space-y-3">
            <p class="text-sm text-blue-700 dark:text-blue-300 font-medium">Proposed change:</p>
            <p class="text-sm text-blue-600 dark:text-blue-400">{@pending_edit.explanation}</p>

            <div class="rounded border bg-background p-2 text-xs font-mono overflow-x-auto max-h-60 overflow-y-auto">
              <%= for {op, lines} <- @pending_edit.diff, line <- lines do %>
                <div class={diff_line_class(op)}>
                  <span class="select-none text-muted-foreground mr-1">{diff_prefix(op)}</span>{line}
                </div>
              <% end %>
            </div>
            <button
              phx-click="open_diff_modal"
              class="text-xs text-primary hover:underline"
            >
              View full diff
            </button>

            <%= if @pending_edit[:validation] do %>
              <div class="flex flex-wrap gap-1.5">
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
              <p class="text-xs text-muted-foreground italic">
                Validation will run after you accept.
              </p>
            <% end %>

            <p class="text-xs text-muted-foreground">
              {format_diff_summary(@pending_edit.diff)}
            </p>

            <div class="flex gap-2">
              <button
                phx-click="accept_edit"
                class="rounded-md bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700"
              >
                Accept
              </button>
              <button
                phx-click="reject_edit"
                class="rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-50"
              >
                Reject
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Quick actions + input --%>
      <div class="border-t p-4 space-y-3">
        <div class="flex flex-wrap gap-1.5">
          <%= for action <- quick_actions(@template_type) do %>
            <button
              type="button"
              phx-click="quick_action"
              phx-value-text={action}
              class="rounded-full border px-2.5 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-accent-foreground"
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

  # -- Sub-components --

  defp render_message(assigns) do
    ~H"""
    <div class={[
      "flex",
      if(@event.role == "user", do: "justify-end", else: "justify-start")
    ]}>
      <div class={[
        "max-w-[80%] rounded-lg px-4 py-3 text-sm whitespace-pre-wrap",
        if(@event.role == "user",
          do: "bg-primary text-primary-foreground",
          else: "bg-muted"
        )
      ]}>
        {@event.content}
      </div>
    </div>
    """
  end

  defp render_tool_group(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border p-4 space-y-3",
      if(@result && !@result.success,
        do: "border-red-300 bg-red-50 dark:border-red-800 dark:bg-red-950",
        else: "border-border bg-card"
      )
    ]}>
      <%!-- Header --%>
      <div class="flex items-center gap-2">
        <%= if @result do %>
          <%= if @result.success do %>
            <span class="text-green-600 text-sm font-bold">&#10003;</span>
          <% else %>
            <span class="text-red-500 text-sm font-bold">&#10007;</span>
          <% end %>
        <% else %>
          <span class="text-muted-foreground text-sm animate-pulse">&#9679;</span>
        <% end %>
        <span class="text-sm font-semibold">{format_tool_display_name(@call.tool)}</span>
        <span class="text-xs text-muted-foreground">{@call.tool}</span>
        <span class="flex-1" />
        <%= if @result && @call[:timestamp] && @result[:timestamp] do %>
          <span class="text-xs text-muted-foreground">{format_duration(@call.timestamp, @result.timestamp)}</span>
        <% end %>
        <%= if @call[:timestamp] do %>
          <span class="text-xs text-muted-foreground">{format_time(@call.timestamp)}</span>
        <% end %>
      </div>

      <%!-- Input section --%>
      <%= if @call.args["code"] || @call.args["test_code"] do %>
        <div class="space-y-2">
          <%= if @call.args["code"] do %>
            <div>
              <p class="text-xs font-medium text-muted-foreground mb-1">Input:</p>
              <pre class="bg-muted rounded-md p-3 font-mono text-xs max-h-[400px] overflow-y-auto overflow-x-auto"><code>{@call.args["code"]}</code></pre>
            </div>
          <% end %>
          <%= if @call.args["test_code"] do %>
            <div>
              <p class="text-xs font-medium text-muted-foreground mb-1">Test code:</p>
              <pre class="bg-muted rounded-md p-3 font-mono text-xs max-h-[400px] overflow-y-auto overflow-x-auto"><code>{@call.args["test_code"]}</code></pre>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Output section --%>
      <%= if @result do %>
        <div>
          <p class="text-xs font-medium text-muted-foreground mb-1">Output:</p>
          <%= if looks_like_code?(@result.content) do %>
            <pre class="bg-muted rounded-md p-3 font-mono text-xs max-h-[400px] overflow-y-auto overflow-x-auto"><code>{@result.content}</code></pre>
          <% else %>
            <p class={[
              "text-sm whitespace-pre-wrap",
              if(!@result.success, do: "text-red-600 dark:text-red-400", else: "")
            ]}>
              {@result.content}
            </p>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_standalone_tool_result(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border p-4 space-y-2",
      if(!@result.success,
        do: "border-red-300 bg-red-50 dark:border-red-800 dark:bg-red-950",
        else: "border-border bg-card"
      )
    ]}>
      <div class="flex items-center gap-2">
        <%= if @result.success do %>
          <span class="text-green-600 text-sm font-bold">&#10003;</span>
        <% else %>
          <span class="text-red-500 text-sm font-bold">&#10007;</span>
        <% end %>
        <span class="text-sm font-semibold">{format_tool_display_name(@result.tool)}</span>
        <span class="text-xs text-muted-foreground">{@result.tool}</span>
      </div>

      <%= if looks_like_code?(@result.content) do %>
        <pre class="bg-muted rounded-md p-3 font-mono text-xs max-h-[400px] overflow-y-auto overflow-x-auto"><code>{@result.content}</code></pre>
      <% else %>
        <p class={[
          "text-sm whitespace-pre-wrap",
          if(!@result.success, do: "text-red-600 dark:text-red-400", else: "")
        ]}>
          {@result.content}
        </p>
      <% end %>
    </div>
    """
  end

  defp render_status(assigns) do
    ~H"""
    <div class="text-center py-1">
      <span class="text-xs text-muted-foreground italic">{@event.content}</span>
    </div>
    """
  end

  # -- Event grouping --

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

  defp event_tag(%{type: :message}), do: :message
  defp event_tag(%{type: :tool_call}), do: :tool_call
  defp event_tag(%{type: :tool_result}), do: :tool_result
  defp event_tag(%{type: :status}), do: :status
  defp event_tag(_), do: :status

  # -- Helpers --

  @spec format_tool_display_name(String.t()) :: String.t()
  defp format_tool_display_name("compile_code"), do: "Compile"
  defp format_tool_display_name("format_code"), do: "Format"
  defp format_tool_display_name("lint_code"), do: "Lint"
  defp format_tool_display_name("generate_tests"), do: "Generate Tests"
  defp format_tool_display_name("run_tests"), do: "Run Tests"
  defp format_tool_display_name("submit_code"), do: "Submit"
  defp format_tool_display_name("read_source"), do: "Read Source"
  defp format_tool_display_name("edit_source"), do: "Edit Source"
  defp format_tool_display_name(name), do: name

  @spec looks_like_code?(String.t() | nil) :: boolean()
  defp looks_like_code?(nil), do: false
  defp looks_like_code?(""), do: false

  defp looks_like_code?(content) when is_binary(content) do
    String.contains?(content, "defmodule") or
      String.contains?(content, "def ") or
      String.contains?(content, "defp ") or
      String.contains?(content, "import ") or
      String.contains?(content, "alias ")
  end

  defp diff_line_class(:ins),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp diff_line_class(:del), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
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

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: ""

  defp format_duration(nil, _), do: ""
  defp format_duration(_, nil), do: ""

  defp format_duration(start_dt, end_dt) do
    diff_ms = DateTime.diff(end_dt, start_dt, :millisecond)

    cond do
      diff_ms < 1000 -> "#{diff_ms}ms"
      diff_ms < 60_000 -> "#{Float.round(diff_ms / 1000, 1)}s"
      true -> "#{div(diff_ms, 60_000)}m #{rem(div(diff_ms, 1000), 60)}s"
    end
  end
end
