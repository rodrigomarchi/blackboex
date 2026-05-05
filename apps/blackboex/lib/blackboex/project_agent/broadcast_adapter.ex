defmodule Blackboex.ProjectAgent.BroadcastAdapter do
  @moduledoc ~S"""
  Uniform broadcast contract bridging the four heterogeneous per-artifact
  KickoffWorker stacks (`Agent`, `FlowAgent`, `PageAgent`, `PlaygroundAgent`)
  into a single LiveView-facing message shape on
  `"project_plan:#{plan.id}"`:

      {:project_task_completed, %{plan_id: plan_id, task_id: task_id,
                                   status: :completed | :failed,
                                   error: term() | nil}}

  ## Verified per-surface terminal contracts

  | artifact_type | topic | terminal tuples (current code paths) |
  |---------------|-------|--------------------------------------|
  | `"api"`         | `run:#{run_id}` | `{:agent_completed, %{run_id, status, ...}}` / `{:agent_failed, %{run_id, error}}` |
  | `"flow"`        | `flow_agent:flow:#{flow_id}` | `{:run_completed, %{run_id, ...}}` / `{:run_failed, %{run_id, reason}}` |
  | `"page"`        | `page_agent:#{org_id}:page:#{page_id}` | `{:run_completed, %{run_id, ...}}` / `{:run_failed, %{run_id, reason}}` |
  | `"playground"`  | `playground_agent:run:#{run_id}` | `{:run_completed, %{run_id, ...}}` / `{:run_failed, %{run_id, reason}}` |

  The `Agent` stack does not broadcast a normalized terminal message on the
  `api:#{api_id}` topic — `Agent.Session/ChainRunner` broadcasts the terminal
  `:agent_completed` / `:agent_failed` on the per-run topic `run:#{run_id}`.
  This adapter therefore subscribes to `run:#{run_id}` for `"api"` tasks.

  ## Idempotency

  `handle_terminal/4` is idempotent on `task.status`: a second call when the
  task is already terminal is a no-op (no DB write, no broadcast, no
  `PlanRunnerWorker` re-enqueue). Restart-safe under Oban retries.

  ## Listener pattern

  M5 ships **option (b) — Poll-only / runner re-entry**: the
  `PlanRunnerWorker` calls `subscribe/2` to register intent for tooling /
  future listeners, but advancement is driven by callers invoking
  `handle_terminal/4` directly when the per-artifact agent completes (the
  per-artifact agents broadcast on PubSub; a future M-N optimization may
  spin a `BroadcastListener` GenServer per task to translate broadcasts in
  real time). For v1 the public seam is `handle_terminal/4` — tests and
  the integration test in M8 drive it directly. Idempotency + Oban retries
  keep this restart-safe.
  """

  alias Blackboex.Plans
  alias Blackboex.Plans.{Plan, PlanTask}
  alias Blackboex.ProjectAgent.PlanRunnerWorker
  alias Blackboex.ProjectConversations

  @typedoc "Translated terminal status from any of the four surfaces."
  @type terminal_status :: :completed | :failed

  @typedoc "Result of `translate_message/2`."
  @type translation :: {:terminal, terminal_status(), term() | nil} | :ignore

  @project_plan_topic "project_plan:"

  @doc """
  Subscribes the calling process to the matching per-artifact topic so it
  can receive the surface's native terminal tuple. Idempotent at the
  `Phoenix.PubSub` level — repeated subscriptions for the same topic from
  the same process are a no-op.

  Returns `:ok` always; subscription failures are folded into `:ok` to
  match the contract used by every existing per-artifact broadcaster.
  """
  @spec subscribe(PlanTask.t(), Plan.t()) :: :ok
  def subscribe(%PlanTask{} = task, %Plan{} = _plan) do
    case Phoenix.PubSub.subscribe(Blackboex.PubSub, topic_for(task)) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  @doc """
  Returns the per-artifact PubSub topic this task's child Run broadcasts on.

  For `"page"` tasks the organization id MUST be passed via
  `task.params["organization_id"]` (the `PageAgent` topic is org-scoped to
  defeat ID-guessing leaks).
  """
  @spec topic_for(PlanTask.t()) :: String.t()
  def topic_for(%PlanTask{artifact_type: "api", child_run_id: run_id}) when is_binary(run_id) do
    "run:#{run_id}"
  end

  def topic_for(%PlanTask{artifact_type: "flow", target_artifact_id: flow_id})
      when is_binary(flow_id) do
    "flow_agent:flow:#{flow_id}"
  end

  def topic_for(%PlanTask{artifact_type: "page", target_artifact_id: page_id, params: params})
      when is_binary(page_id) and is_map(params) do
    org_id = Map.get(params, "organization_id") || Map.get(params, :organization_id)
    "page_agent:#{org_id}:page:#{page_id}"
  end

  def topic_for(%PlanTask{artifact_type: "playground", child_run_id: run_id})
      when is_binary(run_id) do
    "playground_agent:run:#{run_id}"
  end

  @doc """
  Translates a raw per-surface terminal tuple into the uniform
  `{:terminal, :completed | :failed, error_or_nil}` shape, or `:ignore`
  for non-terminal / unrelated messages.

  Only messages whose embedded `:run_id` matches `task.child_run_id` are
  translated; everything else returns `:ignore`.
  """
  @spec translate_message(term(), PlanTask.t()) :: translation()
  def translate_message(message, %PlanTask{child_run_id: run_id}) do
    case message do
      {:agent_completed, %{run_id: ^run_id} = _payload} ->
        {:terminal, :completed, nil}

      {:agent_failed, %{run_id: ^run_id, error: error}} ->
        {:terminal, :failed, error}

      {:agent_failed, %{run_id: ^run_id}} ->
        {:terminal, :failed, nil}

      {:run_completed, %{run_id: ^run_id}} ->
        {:terminal, :completed, nil}

      {:run_failed, %{run_id: ^run_id, reason: reason}} ->
        {:terminal, :failed, reason}

      {:run_failed, %{run_id: ^run_id}} ->
        {:terminal, :failed, nil}

      _ ->
        :ignore
    end
  end

  @doc """
  Marks the task terminal in the DB, re-broadcasts the uniform
  `:project_task_completed` message on `"project_plan:#{"<plan.id>"}"`,
  and re-enqueues `PlanRunnerWorker` for the plan to advance.

  Idempotent on `task.status`: if the task is already terminal, returns
  `:ok` without DB writes, broadcast, or worker enqueue.
  """
  @spec handle_terminal(PlanTask.t(), Plan.t(), terminal_status(), term() | nil) :: :ok
  def handle_terminal(%PlanTask{} = task, %Plan{} = plan, status, error)
      when status in [:completed, :failed] do
    fresh = Plans.get_task!(task.id)

    if terminal?(fresh.status) do
      :ok
    else
      _ = mark_task(fresh, status, error)
      _ = append_task_event(plan, fresh, status, error)
      broadcast_uniform(plan, fresh, status, error)
      enqueue_advance(plan)
      :ok
    end
  end

  @spec append_task_event(Plan.t(), PlanTask.t(), terminal_status(), term() | nil) :: :ok
  defp append_task_event(%Plan{run_id: nil}, _task, _status, _error), do: :ok

  defp append_task_event(%Plan{run_id: run_id}, %PlanTask{} = task, status, error) do
    case ProjectConversations.get_run(run_id) do
      nil ->
        :ok

      run ->
        event_type = if status == :completed, do: "task_completed", else: "task_failed"

        content =
          case status do
            :completed -> "Task completed: #{task.title}"
            :failed -> "Task failed: #{task.title}"
          end

        _ =
          ProjectConversations.append_event(run, %{
            event_type: event_type,
            content: content,
            metadata: %{
              "task_id" => task.id,
              "task_order" => task.order,
              "artifact_type" => task.artifact_type,
              "action" => task.action,
              "error" => format_error(error)
            }
          })

        :ok
    end
  end

  @spec mark_task(PlanTask.t(), terminal_status(), term() | nil) ::
          {:ok, PlanTask.t()} | {:error, Ecto.Changeset.t()}
  defp mark_task(task, :completed, _error), do: Plans.mark_task_done(task)

  defp mark_task(task, :failed, error) do
    Plans.mark_task_failed(task, format_error(error))
  end

  @spec broadcast_uniform(Plan.t(), PlanTask.t(), terminal_status(), term() | nil) :: :ok
  defp broadcast_uniform(%Plan{id: plan_id}, %PlanTask{id: task_id}, status, error) do
    payload = %{plan_id: plan_id, task_id: task_id, status: status, error: error}

    case Phoenix.PubSub.broadcast(
           Blackboex.PubSub,
           @project_plan_topic <> plan_id,
           {:project_task_completed, payload}
         ) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  @spec enqueue_advance(Plan.t()) :: :ok
  defp enqueue_advance(%Plan{id: plan_id}) do
    %{"plan_id" => plan_id}
    |> PlanRunnerWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  @spec terminal?(String.t()) :: boolean()
  defp terminal?(status), do: status in ~w(done failed skipped)

  @spec format_error(term()) :: String.t()
  defp format_error(nil), do: "task failed"
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
