defmodule BlackboexWeb.ProjectAgentLive.Index do
  @moduledoc """
  Project Agent UI — chat-driven.

  The whole interaction (describe goal, review plan, approve, watch
  execution, recover from partial) lives inside a single conversational
  timeline rendered by `BlackboexWeb.Components.Editor.ProjectAgentChatPanel`.
  Events are persisted as `ProjectEvent` rows by the backend workers and
  streamed into the UI via PubSub.

  Plan approval and "Continue from where you stopped" are inline rich
  cards inside the chat — there is no separate form / editor view.

  ## PubSub topics

    * `project_plan:project:#{"<project_id>"}` — subscribed in `mount/3`
      before fetching the active plan, so a `:plan_drafted` race is not
      possible.
    * `project_plan:#{"<plan_id>"}` — subscribed once a plan exists so
      task-level updates flow in.

  ## Inbound messages

    * `{:plan_drafted, payload}` → reload events, swap to the new plan,
      subscribe to plan topic.
    * `{:plan_failed, payload}` → reload events (the failure event is
      already persisted by `KickoffWorker.handle_failure/2`).
    * `{:project_task_dispatched, payload}` → reload events.
    * `{:project_task_completed, payload}` → reload events.
    * `{:plan_status_changed, payload}` → refresh plan struct + events.

  Every PubSub-driven handler reloads events from the DB rather than
  trying to maintain a parallel in-memory log; the DB is the source of
  truth for the conversation timeline.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Editor.ProjectAgentChatPanel

  alias Blackboex.Features
  alias Blackboex.LLM
  alias Blackboex.Plans
  alias Blackboex.ProjectAgent
  alias Blackboex.ProjectAgent.KickoffWorker
  alias Blackboex.ProjectConversations
  alias BlackboexWeb.Components.Editor.ProjectAgentChatPanel

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    project = scope.project

    cond do
      is_nil(project) ->
        {:ok, push_navigate(socket, to: "/")}

      not Features.project_agent_enabled?(project) ->
        {:ok,
         socket
         |> put_flash(:error, "Project Agent is not enabled for this project.")
         |> push_navigate(to: project_path(scope, "/"))}

      true ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Blackboex.PubSub, project_topic(project.id))
        end

        plan = Plans.get_active_plan(project.id) || most_recent_plan(project.id)
        socket = subscribe_to_plan(socket, plan)

        {:ok,
         socket
         |> assign(
           project: project,
           plan: plan,
           planning: nil,
           message_input: "",
           llm_configured?: llm_configured?(project),
           configure_url: configure_url(scope)
         )
         |> stream_events(plan)}
    end
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ── Render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-[calc(100vh-3.5rem)]" id="project-agent-root">
      <.project_agent_chat_panel
        events={@events}
        plan={@plan}
        input={@message_input}
        loading={planning?(@plan, @planning)}
        llm_configured?={@llm_configured?}
        configure_url={@configure_url}
      />
    </div>
    """
  end

  # ── Events ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("chat_input_change", params, socket) do
    msg = Map.get(params, "message", "")
    {:noreply, assign(socket, message_input: msg)}
  end

  def handle_event("send_chat", %{"message" => msg}, socket) do
    msg = String.trim(msg)
    plan = socket.assigns.plan

    cond do
      msg == "" ->
        {:noreply,
         socket
         |> assign(message_input: "")
         |> put_flash(:error, "Type something for the agent to plan.")}

      plan != nil and plan.status in ["draft", "approved", "running"] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "There is already an active plan. Approve it, wait for it to finish, or refresh the page."
         )}

      true ->
        do_start_planning(socket, msg)
    end
  end

  def handle_event("approve_plan", _params, socket) do
    plan = socket.assigns.plan
    user = socket.assigns.current_scope.user

    cond do
      is_nil(plan) ->
        {:noreply, put_flash(socket, :error, "No plan to approve.")}

      plan.status != "draft" ->
        {:noreply,
         put_flash(socket, :error, "This plan is no longer in draft and cannot be approved.")}

      true ->
        do_approve(socket, plan, user)
    end
  end

  def handle_event("continue_from_partial", _params, socket) do
    plan = socket.assigns.plan
    user = socket.assigns.current_scope.user

    cond do
      is_nil(plan) ->
        {:noreply, put_flash(socket, :error, "No plan to continue from.")}

      plan.status not in ["partial", "failed"] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Continue is only available after a plan ends in :partial or :failed."
         )}

      true ->
        do_continue_from_partial(socket, plan, user)
    end
  end

  # ── Info / PubSub ───────────────────────────────────────────────────

  @impl true
  def handle_info({:plan_drafted, payload}, socket) do
    plan = extract_plan(payload)
    socket = subscribe_to_plan(socket, plan)

    {:noreply,
     socket
     |> assign(plan: plan, planning: nil)
     |> stream_events(plan)}
  end

  def handle_info({:plan_failed, _payload}, socket) do
    plan = refresh_plan_from_assign(socket)

    {:noreply,
     socket
     |> assign(plan: plan, planning: nil)
     |> stream_events(plan)}
  end

  def handle_info({:project_task_dispatched, _payload}, socket) do
    plan = refresh_plan_from_assign(socket)
    {:noreply, socket |> assign(plan: plan) |> stream_events(plan)}
  end

  def handle_info({:project_task_completed, _payload}, socket) do
    plan = refresh_plan_from_assign(socket)
    {:noreply, socket |> assign(plan: plan) |> stream_events(plan)}
  end

  def handle_info({:plan_status_changed, _payload}, socket) do
    plan = refresh_plan_from_assign(socket)
    {:noreply, socket |> assign(plan: plan, planning: nil) |> stream_events(plan)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ─────────────────────────────────────────────────────────

  @spec project_topic(Ecto.UUID.t()) :: String.t()
  defp project_topic(project_id), do: "project_plan:project:#{project_id}"

  @spec plan_topic(Ecto.UUID.t()) :: String.t()
  defp plan_topic(plan_id), do: "project_plan:#{plan_id}"

  @spec subscribe_to_plan(Phoenix.LiveView.Socket.t(), nil | Plans.Plan.t()) ::
          Phoenix.LiveView.Socket.t()
  defp subscribe_to_plan(socket, nil), do: socket

  defp subscribe_to_plan(socket, %{id: plan_id}) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Blackboex.PubSub, plan_topic(plan_id))
    end

    socket
  end

  @spec most_recent_plan(Ecto.UUID.t()) :: Plans.Plan.t() | nil
  defp most_recent_plan(project_id) do
    case Plans.list_plans_for_project(project_id, limit: 1) do
      [plan | _] -> plan
      [] -> nil
    end
  end

  # The chat timeline is sourced from `ProjectEvent` rows. The most
  # recent (or active) plan's `run_id` anchors which run we read events
  # from; if no plan exists, we read events from the latest run on the
  # latest active conversation.
  @spec stream_events(Phoenix.LiveView.Socket.t(), Plans.Plan.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp stream_events(socket, plan) do
    project = socket.assigns.project
    raw_events = load_events(project, plan)
    plan_with_tasks = preload_plan(plan)

    entries =
      raw_events
      |> Enum.map(&ProjectAgentChatPanel.entry_from_event/1)
      |> ensure_terminal_card(plan_with_tasks)

    socket
    |> assign(plan: plan_with_tasks, events: entries)
  end

  # When the plan is terminal (`:partial` / `:failed` / `:done`) but the
  # event log does not yet contain a corresponding terminal event (rare
  # in production — happens in tests + when a plan transitions before
  # any event is appended), synthesize one so the chat-side card +
  # "Continue from where you stopped" button render correctly.
  @spec ensure_terminal_card(list(map()), Plans.Plan.t() | nil) :: list(map())
  defp ensure_terminal_card(entries, nil), do: entries

  defp ensure_terminal_card(entries, %Plans.Plan{} = plan) do
    case plan.status do
      "partial" -> append_if_missing(entries, :failed, plan, halted_message(plan))
      "failed" -> append_if_missing(entries, :failed, plan, halted_message(plan))
      "done" -> append_if_missing(entries, :completed, plan, "Plan completed")
      _ -> entries
    end
  end

  @spec append_if_missing(list(map()), atom(), Plans.Plan.t(), String.t()) :: list(map())
  defp append_if_missing(entries, kind, plan, content) do
    if Enum.any?(entries, &(&1.kind == kind)) do
      entries
    else
      synthetic = %{
        id: "virtual:#{kind}:#{plan.id}",
        kind: kind,
        content: content,
        metadata: %{"plan_status" => plan.status, "reason" => plan.failure_reason}
      }

      entries ++ [synthetic]
    end
  end

  @spec halted_message(Plans.Plan.t()) :: String.t()
  defp halted_message(%Plans.Plan{failure_reason: reason})
       when is_binary(reason) and reason != "",
       do: "Plan halted: #{reason}"

  defp halted_message(_), do: "Plan halted before completing all tasks."

  @spec preload_plan(Plans.Plan.t() | nil) :: Plans.Plan.t() | nil
  defp preload_plan(nil), do: nil
  defp preload_plan(%Plans.Plan{} = plan), do: Blackboex.Repo.preload(plan, :tasks, force: true)

  @spec load_events(Blackboex.Projects.Project.t(), Plans.Plan.t() | nil) :: [map()]
  defp load_events(_project, %Plans.Plan{run_id: run_id}) when is_binary(run_id) do
    ProjectConversations.list_events(run_id)
  end

  defp load_events(project, _plan) do
    case ProjectConversations.get_active_conversation(project.id) do
      nil ->
        []

      conv ->
        case ProjectConversations.list_runs(conv.id) do
          [%{id: run_id} | _] -> ProjectConversations.list_events(run_id)
          _ -> []
        end
    end
  end

  @spec refresh_plan_from_assign(Phoenix.LiveView.Socket.t()) :: Plans.Plan.t() | nil
  defp refresh_plan_from_assign(%{assigns: %{plan: nil, project: project}}) do
    most_recent_plan(project.id)
  end

  defp refresh_plan_from_assign(%{assigns: %{plan: %{id: id}}}) do
    Plans.get_plan!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  @spec extract_plan(any()) :: Plans.Plan.t() | nil
  defp extract_plan(%Plans.Plan{} = plan), do: plan
  defp extract_plan(%{plan: %Plans.Plan{} = plan}), do: plan
  defp extract_plan(%{id: id}) when is_binary(id), do: Plans.get_plan!(id)
  defp extract_plan(_), do: nil

  @spec planning?(Plans.Plan.t() | nil, atom() | nil) :: boolean()
  defp planning?(nil, :enqueued), do: true
  defp planning?(nil, _), do: false
  defp planning?(%{status: status}, _), do: status in ["approved", "running"]

  @spec llm_configured?(Blackboex.Projects.Project.t()) :: boolean()
  defp llm_configured?(%{id: project_id}) do
    case LLM.Config.client_for_project(project_id) do
      {:ok, _module, _opts} -> true
      {:error, _} -> false
    end
  end

  @spec configure_url(Blackboex.Accounts.Scope.t()) :: String.t()
  defp configure_url(scope) do
    project_path(scope, "/llm-integrations")
  end

  # ── Action helpers ──────────────────────────────────────────────────

  @spec do_start_planning(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_start_planning(socket, msg) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user

    case ProjectAgent.start_planning(project, user, msg) do
      {:ok, _conv, _run} ->
        {:noreply,
         socket
         |> assign(message_input: "", planning: :enqueued)
         |> stream_events(socket.assigns.plan)}

      {:error, reason} ->
        require Logger
        Logger.warning("ProjectAgent.start_planning failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to start the planner. Please try again.")}
    end
  end

  @spec do_approve(
          Phoenix.LiveView.Socket.t(),
          Plans.Plan.t(),
          Blackboex.Accounts.User.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_approve(socket, plan, user) do
    case ProjectAgent.approve_and_run(plan, user, %{markdown_body: plan.markdown_body}) do
      {:ok, approved} ->
        {:noreply,
         socket
         |> assign(plan: approved)
         |> stream_events(approved)
         |> put_flash(:info, "Plan approved — execution starting.")}

      {:error, :concurrent_active_plan} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Another plan is already active for this project. Please wait for it to finish."
         )}

      {:error, :already_terminal} ->
        {:noreply,
         put_flash(socket, :error, "This plan is no longer in draft and cannot be approved.")}

      {:error, reason} ->
        require Logger
        Logger.warning("ProjectAgent.approve_and_run failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to approve the plan. Please try again.")}
    end
  end

  @spec do_continue_from_partial(
          Phoenix.LiveView.Socket.t(),
          Plans.Plan.t(),
          Blackboex.Accounts.User.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_continue_from_partial(socket, plan, user) do
    project = socket.assigns.project

    case Plans.start_continuation(plan, user) do
      {:ok, draft} ->
        _ = enqueue_continuation_kickoff(project, user, plan, draft)

        {:noreply,
         socket
         |> assign(plan: draft, planning: :enqueued)
         |> stream_events(draft)
         |> subscribe_to_plan(draft)
         |> put_flash(:info, "Continuation draft created — refining tasks now.")}

      {:error, :parent_still_active} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot continue while the previous plan is still active."
         )}

      {:error, reason} ->
        require Logger
        Logger.warning("ProjectAgent.continue_from_partial failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to start a continuation. Please try again.")}
    end
  end

  @spec enqueue_continuation_kickoff(
          Blackboex.Projects.Project.t(),
          Blackboex.Accounts.User.t(),
          Plans.Plan.t(),
          Plans.Plan.t()
        ) :: {:ok, Oban.Job.t()} | {:error, term()}
  defp enqueue_continuation_kickoff(project, user, parent_plan, draft) do
    %{
      "project_id" => project.id,
      "organization_id" => project.organization_id,
      "user_id" => user.id,
      "user_message" => parent_plan.user_message,
      "continuation" => true,
      "parent_plan_id" => parent_plan.id,
      "plan_id" => draft.id
    }
    |> KickoffWorker.new()
    |> Oban.insert()
  end
end
