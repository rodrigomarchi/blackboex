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

  import BlackboexWeb.Components.Badge

  import BlackboexWeb.Components.Editor.Chat.Panel,
    only: [agent_chat_panel: 1, message_step: 1, thinking_step: 1]

  import BlackboexWeb.Components.Shared.Panel
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.StatusDot

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
    assigns =
      assigns
      |> Map.put(:timeline_empty, assigns.events == [] and not assigns.loading)
      |> Map.put(:new_chat_disabled, new_chat_disabled?(assigns))

    ~H"""
    <.agent_chat_panel
      title="Project Agent"
      icon="hero-sparkles"
      timeline_id="project-agent-chat-timeline"
      empty_description="Describe what you want to build. The agent will draft a multi-step plan touching APIs, flows, pages, or playgrounds — you review and approve before any code runs."
      timeline_empty={@timeline_empty}
      loading={@loading}
      llm_configured?={@llm_configured?}
      configure_url={@configure_url}
      input={@input}
      input_name="message"
      input_placeholder="Describe the change you want — the agent will plan it first."
      input_disabled={@loading or not @llm_configured?}
      submit_disabled={@loading or not @llm_configured?}
      show_new_conversation?={true}
      new_conversation_event="new_chat"
      new_conversation_disabled={@new_chat_disabled}
    >
      <:timeline>
        <div
          data-component="agent-chat-timeline"
          class="relative ml-7 mr-4 my-3 border-l border-border pl-4"
        >
          <%= for entry <- @events do %>
            <.entry_step entry={entry} plan={@plan} loading={@loading} />
          <% end %>

          <.thinking_step :if={@loading} label="Agent thinking..." />
        </div>
      </:timeline>
    </.agent_chat_panel>
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
    <.message_step message={entry_message(@entry, "user")} />
    """
  end

  # ── Assistant bubble ─────────────────────────────────────────────

  defp assistant_bubble(assigns) do
    ~H"""
    <.message_step message={entry_message(@entry, "assistant")} />
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
    <.panel
      variant="default"
      class="space-y-3 border-primary/40 bg-primary/5"
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
        <.badge variant="status" size="xs" class={"shrink-0 #{plan_status_class(@plan_status)}"}>
          {humanize_status(@plan_status)}
        </.badge>
      </div>

      <%= if @plan_tasks != [] do %>
        <ol class="space-y-2 text-xs">
          <%= for task <- Enum.sort_by(@plan_tasks, & &1.order) do %>
            <li class="flex items-start gap-2">
              <span class="shrink-0 mt-0.5 inline-flex size-5 items-center justify-center rounded-full bg-background text-2xs font-mono text-muted-foreground border">
                {task.order + 1}
              </span>
              <div class="min-w-0 flex-1 space-y-1">
                <div class="text-xs font-medium text-foreground">{task.title}</div>
                <div class="text-2xs text-muted-foreground">
                  {String.upcase(task.action)} {task.artifact_type}
                  <span :if={task.target_artifact_id} class="font-mono">
                    · {String.slice(task.target_artifact_id, 0, 8)}
                  </span>
                </div>
                <ul
                  :if={(task.acceptance_criteria || []) != []}
                  class="ml-1 list-disc space-y-0.5 pl-4 text-2xs text-muted-foreground"
                  data-role="task-criteria"
                >
                  <li :for={criterion <- task.acceptance_criteria}>{criterion}</li>
                </ul>
              </div>
              <.badge variant="status" size="xs" class={"shrink-0 #{task_status_class(task.status)}"}>
                {task.status}
              </.badge>
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
    </.panel>
    """
  end

  # ── Task in-progress ─────────────────────────────────────────────

  defp task_running(assigns) do
    ~H"""
    <div class="relative pb-2 pt-1" data-role="task-running">
      <div class="timeline-dot-sm top-3 border-info" />
      <div class="ml-2">
        <.status_dot status="running" label={@entry.content} pulse class="max-w-full" />
      </div>
    </div>
    """
  end

  # ── Task done ───────────────────────────────────────────────────

  defp task_done(assigns) do
    ~H"""
    <div class="relative pb-2 pt-1" data-role="task-done">
      <div class="timeline-dot-sm top-3 border-success" />
      <.alert_banner variant="success" icon="hero-check-circle" class="ml-2 px-3 py-2 text-xs">
        {@entry.content}
      </.alert_banner>
    </div>
    """
  end

  # ── Task failed ──────────────────────────────────────────────────

  defp task_failed(assigns) do
    error = (assigns.entry[:metadata] || %{})["error"]
    assigns = assign(assigns, :error, error)

    ~H"""
    <div class="relative pb-2 pt-1" data-role="task-failed">
      <div class="timeline-dot-sm top-3 border-destructive" />
      <.alert_banner
        variant="destructive"
        icon="hero-x-circle"
        class="ml-2 space-y-1 px-3 py-2 text-xs"
      >
        <span class="font-medium">{@entry.content}</span>
        <p :if={@error not in [nil, ""]} class="mt-1 font-mono text-2xs text-destructive/80">
          {@error}
        </p>
      </.alert_banner>
    </div>
    """
  end

  # ── Plan completed ───────────────────────────────────────────────

  defp plan_completed(assigns) do
    ~H"""
    <div class="relative pb-2 pt-1" data-role="plan-completed">
      <div class="timeline-dot-sm top-3 border-success" />
      <.alert_banner
        variant="success"
        icon="hero-check-badge"
        class="ml-2 px-3 py-2 text-xs font-medium"
      >
        {@entry.content}
      </.alert_banner>
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
    <div class="relative pb-2 pt-1" data-role="plan-halted">
      <div class="timeline-dot-sm top-3 border-destructive" />
      <.alert_banner
        variant="destructive"
        icon="hero-exclamation-triangle"
        class="ml-2 space-y-2 px-3 py-2 text-xs"
      >
        <span class="font-medium">{@entry.content}</span>
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
      </.alert_banner>
    </div>
    """
  end

  defp placeholder(assigns) do
    ~H"""
    <div class="text-2xs text-muted-foreground italic">{@entry[:content]}</div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────

  # Disable "New conversation" only while the plan is actively executing — at
  # that point archiving the conversation would orphan the running plan_runner.
  # Draft/partial/failed/done plans (and no-plan states) are safe to discard.
  @spec new_chat_disabled?(map()) :: boolean()
  defp new_chat_disabled?(%{loading: true}), do: true

  defp new_chat_disabled?(%{plan: %{status: status}}) when status in ["approved", "running"],
    do: true

  defp new_chat_disabled?(_), do: false

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

  defp entry_message(entry, role) do
    %{
      role: role,
      content: entry.content,
      timestamp: Map.get(entry, :timestamp)
    }
  end

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
