defmodule BlackboexWeb.Components.Editor.ProjectAgentChatPanel do
  @moduledoc """
  Conversational chat panel for the Project Agent.

  Renders a `ProjectConversation` timeline as a chat (user / assistant
  messages plus rich event types like `plan_drafted`, `task_dispatched`,
  `task_completed`, `task_failed`, `completed`, `failed`). The plan
  approval card and the "Continue from where you stopped" button both
  live INSIDE the conversation as inline rich messages — there is no
  separate plan editor view.

  Visually consistent with `FlowChatPanel` / `PageChatPanel` /
  `PlaygroundChatPanel`: same `ChatAutoScroll` hook, same `inline_input`
  composer, same `LlmNotConfiguredBanner` for missing API keys.

  ## Event contract (parent LiveView)

    * `phx-submit="send_chat"` on the form (value under `"message"`)
    * `phx-change="chat_input_change"` on the form
    * `phx-click="approve_plan"` on the inline plan card (when status is `:draft`)
    * `phx-click="continue_from_partial"` on the inline halt message
      (when plan status is `:partial` or `:failed`)
  """

  use BlackboexWeb, :html

  import BlackboexWeb.Components.Shared.LlmNotConfiguredBanner
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.SectionHeading

  @typedoc """
  An entry in the chat timeline. Every entry has an `:id` (used for
  `Phoenix.LiveView.stream`) and a `:kind` discriminator.
  """
  @type entry :: %{
          required(:id) => String.t(),
          required(:kind) => atom(),
          optional(any) => any
        }

  attr :events, :list,
    required: true,
    doc:
      "Chat entries in chronological order. Each is the output of `entry_from_event/2` or " <>
        "an in-memory pending bubble produced by the LiveView."

  attr :plan, :any, default: nil, doc: "The active `Plan` struct, or nil if none."
  attr :input, :string, default: ""
  attr :loading, :boolean, default: false
  attr :llm_configured?, :boolean, default: true
  attr :configure_url, :string, default: nil

  @spec project_agent_chat_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def project_agent_chat_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full overflow-hidden bg-background">
      <%!-- Header --%>
      <div class="flex items-center justify-between border-b px-4 py-2 shrink-0 bg-card">
        <.section_heading icon="hero-sparkles" icon_class="size-4 text-primary">
          Project Agent
        </.section_heading>
      </div>

      <%!-- Scrollable timeline area --%>
      <div
        class="flex-1 min-h-0 overflow-y-auto"
        id="project-agent-chat-timeline"
        phx-hook="ChatAutoScroll"
      >
        <div :if={!@llm_configured?} class="px-3 pt-3">
          <.llm_not_configured_banner project_url={@configure_url} />
        </div>

        <%= if @events == [] and not @loading do %>
          <div class="text-center py-12 px-4 max-w-md mx-auto">
            <p class="text-muted-description text-sm">
              Describe what you want to build. The agent will draft a multi-step plan
              touching APIs, flows, pages, or playgrounds — you review and approve before
              any code runs.
            </p>
          </div>
        <% else %>
          <div class="px-4 py-3 space-y-3">
            <%= for entry <- @events do %>
              <.entry_step entry={entry} plan={@plan} loading={@loading} />
            <% end %>

            <%= if @loading do %>
              <div class="flex items-center gap-2 px-2 py-1">
                <div class="size-2 rounded-full bg-info animate-pulse" />
                <span class="text-xs text-muted-foreground animate-pulse">
                  Agent thinking...
                </span>
              </div>
            <% end %>
          </div>
        <% end %>

        <div class="h-4" />
      </div>

      <%!-- Composer --%>
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
            placeholder="Describe the change you want — the agent will plan it first."
            class="flex-1 rounded-md"
            autocomplete="off"
            disabled={@loading or not @llm_configured?}
          />
          <.button
            type="submit"
            variant="primary"
            disabled={@loading or not @llm_configured?}
            class="rounded-md"
          >
            Send
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  # ── Single entry dispatch ────────────────────────────────────────

  attr :entry, :map, required: true
  attr :plan, :any, default: nil
  attr :loading, :boolean, default: false

  defp entry_step(%{entry: %{kind: :user_message}} = assigns), do: user_bubble(assigns)
  defp entry_step(%{entry: %{kind: :assistant_message}} = assigns), do: assistant_bubble(assigns)
  defp entry_step(%{entry: %{kind: :plan_drafted}} = assigns), do: plan_card(assigns)
  defp entry_step(%{entry: %{kind: :task_dispatched}} = assigns), do: task_running(assigns)
  defp entry_step(%{entry: %{kind: :task_completed}} = assigns), do: task_done(assigns)
  defp entry_step(%{entry: %{kind: :task_failed}} = assigns), do: task_failed(assigns)
  defp entry_step(%{entry: %{kind: :completed}} = assigns), do: plan_completed(assigns)
  defp entry_step(%{entry: %{kind: :failed}} = assigns), do: plan_halted(assigns)
  defp entry_step(assigns), do: placeholder(assigns)

  # ── User bubble ──────────────────────────────────────────────────

  defp user_bubble(assigns) do
    ~H"""
    <div class="flex justify-end" data-role="chat-user">
      <div class="rounded-2xl rounded-tr-sm bg-primary text-primary-foreground px-3 py-2 max-w-[80%] text-sm whitespace-pre-wrap break-words">
        {@entry.content}
      </div>
    </div>
    """
  end

  # ── Assistant bubble ─────────────────────────────────────────────

  defp assistant_bubble(assigns) do
    ~H"""
    <div class="flex" data-role="chat-assistant">
      <div class="rounded-2xl rounded-tl-sm bg-muted px-3 py-2 max-w-[80%] text-sm whitespace-pre-wrap break-words">
        {@entry.content}
      </div>
    </div>
    """
  end

  # ── Plan card (approval lives here) ──────────────────────────────

  defp plan_card(assigns) do
    plan = assigns[:plan]

    assigns =
      assigns
      |> assign(:plan_status, plan && plan.status)
      |> assign(:plan_tasks, (plan && plan.tasks) || assigns.entry[:tasks] || [])
      |> assign(:plan_title, (plan && plan.title) || assigns.entry[:content] || "Plan drafted")

    ~H"""
    <div
      class="rounded-lg border border-primary/40 bg-primary/5 p-4 space-y-3"
      data-role="plan-card"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="space-y-1 min-w-0">
          <div class="flex items-center gap-2">
            <.icon name="hero-document-text" class="size-4 text-primary shrink-0" />
            <span class="text-xs font-semibold uppercase tracking-wide text-primary">
              Plan drafted
            </span>
          </div>
          <h3 class="text-sm font-semibold text-foreground">{@plan_title}</h3>
        </div>
        <span class={[
          "shrink-0 rounded-full px-2 py-0.5 text-2xs font-medium",
          plan_status_class(@plan_status)
        ]}>
          {humanize_status(@plan_status)}
        </span>
      </div>

      <%= if @plan_tasks != [] do %>
        <ol class="space-y-1.5 text-xs">
          <%= for task <- Enum.sort_by(@plan_tasks, & &1.order) do %>
            <li class="flex items-start gap-2">
              <span class="shrink-0 mt-0.5 inline-flex size-5 items-center justify-center rounded-full bg-background text-2xs font-mono text-muted-foreground border">
                {task.order + 1}
              </span>
              <div class="min-w-0 flex-1">
                <div class="text-xs font-medium text-foreground">{task.title}</div>
                <div class="text-2xs text-muted-foreground">
                  {String.upcase(task.action)} {task.artifact_type}
                  <span :if={task.target_artifact_id} class="font-mono">
                    · {String.slice(task.target_artifact_id, 0, 8)}
                  </span>
                </div>
              </div>
              <span class={[
                "shrink-0 rounded px-1.5 py-0.5 text-2xs",
                task_status_class(task.status)
              ]}>
                {task.status}
              </span>
            </li>
          <% end %>
        </ol>
      <% end %>

      <%= if @plan_status == "draft" do %>
        <div class="flex items-center justify-end gap-2 pt-2 border-t border-primary/20">
          <.button
            type="button"
            variant="primary"
            size="compact"
            phx-click="approve_plan"
            class="rounded-md"
          >
            Approve &amp; run
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Task in-progress ─────────────────────────────────────────────

  defp task_running(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-xs text-muted-foreground" data-role="task-running">
      <div class="size-2 rounded-full bg-info animate-pulse shrink-0" />
      <span>{@entry.content}</span>
    </div>
    """
  end

  # ── Task done ───────────────────────────────────────────────────

  defp task_done(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-xs text-success-foreground" data-role="task-done">
      <.icon name="hero-check-circle" class="size-4 text-success shrink-0" />
      <span>{@entry.content}</span>
    </div>
    """
  end

  # ── Task failed ──────────────────────────────────────────────────

  defp task_failed(assigns) do
    error = (assigns.entry[:metadata] || %{})["error"]
    assigns = assign(assigns, :error, error)

    ~H"""
    <div
      class="rounded-md border border-destructive/40 bg-destructive/5 p-2.5 text-xs space-y-1"
      data-role="task-failed"
    >
      <div class="flex items-center gap-2 font-medium text-destructive">
        <.icon name="hero-x-circle" class="size-4 shrink-0" />
        <span>{@entry.content}</span>
      </div>
      <p :if={@error not in [nil, ""]} class="text-2xs text-destructive/80 ml-6 font-mono">
        {@error}
      </p>
    </div>
    """
  end

  # ── Plan completed ───────────────────────────────────────────────

  defp plan_completed(assigns) do
    ~H"""
    <div
      class="rounded-md border border-success/40 bg-success/5 p-3 text-xs flex items-center gap-2 font-medium text-success-foreground"
      data-role="plan-completed"
    >
      <.icon name="hero-check-badge" class="size-4 text-success shrink-0" />
      <span>{@entry.content}</span>
    </div>
    """
  end

  # ── Plan halted (failed/partial) ─────────────────────────────────

  defp plan_halted(assigns) do
    plan = assigns[:plan]

    assigns =
      assigns
      |> assign(:can_continue?, plan && plan.status in ["partial", "failed"])

    ~H"""
    <div
      class="rounded-md border border-destructive/40 bg-destructive/5 p-3 text-xs space-y-2"
      data-role="plan-halted"
    >
      <div class="flex items-center gap-2 font-medium text-destructive">
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
        <span>{@entry.content}</span>
      </div>
      <%= if @can_continue? do %>
        <div class="flex justify-end">
          <.button
            type="button"
            variant="outline"
            size="compact"
            phx-click="continue_from_partial"
            class="rounded-md"
          >
            Continue from where you stopped
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  defp placeholder(assigns) do
    ~H"""
    <div class="text-2xs text-muted-foreground italic">{@entry[:content]}</div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp plan_status_class("draft"), do: "bg-primary/15 text-primary"
  defp plan_status_class("approved"), do: "bg-info/15 text-info-foreground"
  defp plan_status_class("running"), do: "bg-info/15 text-info-foreground"
  defp plan_status_class("done"), do: "bg-success/15 text-success-foreground"
  defp plan_status_class("partial"), do: "bg-warning/15 text-warning-foreground"
  defp plan_status_class("failed"), do: "bg-destructive/15 text-destructive"
  defp plan_status_class(_), do: "bg-muted text-muted-foreground"

  defp humanize_status(nil), do: "—"
  defp humanize_status(status), do: status |> to_string() |> String.upcase()

  defp task_status_class("pending"), do: "bg-muted text-muted-foreground"
  defp task_status_class("running"), do: "bg-info/15 text-info-foreground"
  defp task_status_class("done"), do: "bg-success/15 text-success-foreground"
  defp task_status_class("failed"), do: "bg-destructive/15 text-destructive"
  defp task_status_class("skipped"), do: "bg-muted text-muted-foreground italic"
  defp task_status_class(_), do: "bg-muted text-muted-foreground"

  @doc """
  Translates a `ProjectEvent` row into a chat-timeline entry. Used by
  the LiveView when seeding the stream from the DB or when a new event
  arrives via PubSub.
  """
  @spec entry_from_event(map()) :: entry()
  def entry_from_event(%{event_type: type, id: id, content: content, metadata: metadata}) do
    base = %{id: id, content: content, metadata: metadata, kind: type_to_kind(type)}

    Map.merge(base, extra_for_kind(base.kind, metadata))
  end

  defp type_to_kind("user_message"), do: :user_message
  defp type_to_kind("assistant_message"), do: :assistant_message
  defp type_to_kind("plan_drafted"), do: :plan_drafted
  defp type_to_kind("plan_approved"), do: :plan_approved
  defp type_to_kind("task_dispatched"), do: :task_dispatched
  defp type_to_kind("task_completed"), do: :task_completed
  defp type_to_kind("task_failed"), do: :task_failed
  defp type_to_kind("completed"), do: :completed
  defp type_to_kind("failed"), do: :failed
  defp type_to_kind(_), do: :unknown

  defp extra_for_kind(_kind, _metadata), do: %{}
end
