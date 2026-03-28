defmodule BlackboexWeb.Components.ChatPanel do
  @moduledoc """
  LiveComponent for the chat panel used in conversational API editing.
  Displays message history, streaming tokens, pipeline progress, and pending edits.
  """

  use BlackboexWeb, :live_component

  alias Blackboex.Apis.DiffEngine

  import BlackboexWeb.Components.PipelineStatus
  import BlackboexWeb.Components.ValidationDashboard, only: [validation_badge: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center justify-between border-b px-4 py-2">
        <h2 class="text-sm font-semibold">Chat</h2>
        <button
          phx-click="clear_conversation"
          class="text-xs text-muted-foreground hover:text-foreground"
          data-confirm="Clear conversation? Code will not be affected."
        >
          New conversation
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-3 space-y-3" id="chat-messages">
        <%= if @messages == [] and @pending_edit == nil and @streaming_tokens == "" do %>
          <p class="text-xs text-muted-foreground text-center py-8">
            Describe the changes you want in the code.
          </p>
        <% else %>
          <%= for msg <- @messages do %>
            <div class={[
              "flex",
              if(msg["role"] == "user", do: "justify-end", else: "justify-start")
            ]}>
              <div class={[
                "max-w-[85%] rounded-lg px-3 py-2 text-xs",
                if(msg["role"] == "user",
                  do: "bg-primary text-primary-foreground",
                  else: "bg-muted"
                )
              ]}>
                {msg["content"]}
              </div>
            </div>
          <% end %>
        <% end %>

        <%!-- Streaming tokens (real-time LLM output) --%>
        <%= if @loading && @streaming_tokens != "" do %>
          <div class="flex justify-start">
            <div class="max-w-[85%] rounded-lg bg-muted px-3 py-2 text-xs">
              <pre class="whitespace-pre-wrap font-mono text-[11px]"><code>{@streaming_tokens}</code></pre>
              <span class="inline-block w-1.5 h-3.5 bg-primary animate-pulse ml-0.5" />
            </div>
          </div>
        <% end %>

        <%!-- Pipeline progress (after streaming, during validation) --%>
        <%= if @pipeline_status && @pipeline_status not in [:generating_code, :done, :failed] && @loading do %>
          <div class="flex justify-start">
            <div class="rounded-lg border border-blue-200 bg-blue-50 dark:border-blue-800 dark:bg-blue-950 px-3 py-2">
              <.pipeline_progress_steps status={@pipeline_status} />
            </div>
          </div>
        <% end %>

        <%!-- Agent events timeline --%>
        <%= if @agent_events != [] do %>
          <div class="rounded-lg border bg-muted/50 px-3 py-2 space-y-1">
            <%= for event <- Enum.reverse(@agent_events) do %>
              <div class="flex items-center gap-1.5 text-[11px]">
                <%= case event do %>
                  <% %{type: :tool_result, success: true, tool: tool, summary: summary} -> %>
                    <span class="text-green-600">&#10003;</span>
                    <span class="text-muted-foreground">{format_tool_name(tool)}</span>
                    <span :if={summary} class="text-muted-foreground truncate max-w-[200px]">
                      — {summary}
                    </span>
                  <% %{type: :tool_result, success: false, tool: tool, summary: summary} -> %>
                    <span class="text-red-500">&#10007;</span>
                    <span class="text-muted-foreground">{format_tool_name(tool)}</span>
                    <span :if={summary} class="text-red-500 truncate max-w-[200px]">
                      — {summary}
                    </span>
                  <% %{type: :message, content: content} -> %>
                    <span class="text-blue-500">&#9679;</span>
                    <span class="text-muted-foreground truncate max-w-[240px]">{content}</span>
                  <% _ -> %>
                    <span class="text-muted-foreground">&#9679;</span>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Loading state (no streaming yet) --%>
        <%= if @loading && @streaming_tokens == "" && @pipeline_status in [nil, :generating_code] do %>
          <div class="flex justify-start">
            <div class="bg-muted rounded-lg px-3 py-2 text-xs text-muted-foreground animate-pulse">
              Thinking...
            </div>
          </div>
        <% end %>

        <%!-- Pending edit with validation --%>
        <%= if @pending_edit do %>
          <div class="rounded-lg border border-blue-200 bg-blue-50 dark:border-blue-800 dark:bg-blue-950 p-3 space-y-2">
            <p class="text-xs text-blue-700 dark:text-blue-300 font-medium">Proposed change:</p>
            <p class="text-xs text-blue-600 dark:text-blue-400">{@pending_edit.explanation}</p>

            <%!-- Code diff (compact preview) --%>
            <div class="rounded border bg-background p-2 text-xs font-mono overflow-x-auto max-h-40 overflow-y-auto">
              <%= for {op, lines} <- @pending_edit.diff, line <- lines do %>
                <div class={diff_line_class(op)}>
                  <span class="select-none text-muted-foreground mr-1">{diff_prefix(op)}</span>{line}
                </div>
              <% end %>
            </div>
            <button
              phx-click="open_diff_modal"
              class="text-[10px] text-primary hover:underline"
            >
              View full diff
            </button>

            <%!-- Validation badges --%>
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
              <p class="text-[10px] text-muted-foreground italic">
                Validation will run after you accept.
              </p>
            <% end %>

            <p class="text-xs text-muted-foreground">
              {format_diff_summary(@pending_edit.diff)}
            </p>

            <div class="flex gap-2">
              <button
                phx-click="accept_edit"
                class="rounded-md bg-green-600 px-3 py-1 text-xs font-medium text-white hover:bg-green-700"
              >
                Accept
              </button>
              <button
                phx-click="reject_edit"
                class="rounded-md border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50"
              >
                Reject
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <div class="border-t p-3 space-y-2">
        <div class="flex flex-wrap gap-1">
          <%= for action <- quick_actions(@template_type) do %>
            <button
              type="button"
              phx-click="quick_action"
              phx-value-text={action}
              class="rounded-full border px-2 py-0.5 text-xs text-muted-foreground hover:bg-accent hover:text-accent-foreground"
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
            class="flex-1 rounded-md border bg-background px-3 py-1.5 text-xs"
            autocomplete="off"
            disabled={@loading}
          />
          <button
            type="submit"
            disabled={@loading}
            class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
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

  defp format_tool_name("compile_code"), do: "Compiling"
  defp format_tool_name("format_code"), do: "Formatting"
  defp format_tool_name("lint_code"), do: "Linting"
  defp format_tool_name("generate_tests"), do: "Generating tests"
  defp format_tool_name("run_tests"), do: "Running tests"
  defp format_tool_name("submit_code"), do: "Submitting"
  defp format_tool_name(name), do: name

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
