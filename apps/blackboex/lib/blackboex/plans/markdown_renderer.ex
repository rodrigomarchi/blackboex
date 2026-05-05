defmodule Blackboex.Plans.MarkdownRenderer do
  @moduledoc """
  Pure renderer that turns a `Plan` (with preloaded tasks) into a
  human-editable markdown body. Output is the canonical surface for the
  draft-plan editor and is round-trip-validated by
  `Blackboex.Plans.MarkdownParser` on approval.

  Format (stable — `MarkdownParser` parses exactly what this renderer
  emits):

      # {plan.title}

      _Project ID: {plan.project_id}_

      > {plan.failure_reason}                          # only if non-nil

      ## 1. {task.title}
      - artifact_type: {task.artifact_type}
      - action: {task.action}
      - target_artifact_id: {task.target_artifact_id || "nil"}
      - params: {inspect(task.params)}
      - acceptance_criteria:
        - {criterion 1}
        - {criterion 2}

  The renderer never escapes user data — it assumes the planner emits
  safe values. The markdown is treated as plain text everywhere downstream
  (LiveView Monaco editor, `MarkdownParser`).
  """

  alias Blackboex.Plans.{Plan, PlanTask}

  @spec render(Plan.t()) :: String.t()
  def render(%Plan{} = plan) do
    tasks = sorted_tasks(plan)

    [
      header(plan),
      Enum.map(tasks, &render_task/1)
    ]
    |> IO.iodata_to_binary()
  end

  defp sorted_tasks(%Plan{tasks: %Ecto.Association.NotLoaded{}}), do: []
  defp sorted_tasks(%Plan{tasks: nil}), do: []

  defp sorted_tasks(%Plan{tasks: tasks}) when is_list(tasks) do
    Enum.sort_by(tasks, & &1.order)
  end

  defp header(%Plan{title: title, project_id: project_id, failure_reason: reason}) do
    [
      "# ",
      title || "",
      "\n\n_Project ID: ",
      to_string(project_id),
      "_\n",
      render_failure_reason(reason),
      "\n"
    ]
  end

  defp render_failure_reason(nil), do: ""
  defp render_failure_reason(""), do: ""

  defp render_failure_reason(reason) when is_binary(reason) do
    ["\n> Prior failure: ", reason, "\n"]
  end

  defp render_task(%PlanTask{} = task) do
    [
      "## ",
      Integer.to_string(task.order + 1),
      ". ",
      task.title || "",
      "\n",
      "- artifact_type: ",
      task.artifact_type || "",
      "\n",
      "- action: ",
      task.action || "",
      "\n",
      "- target_artifact_id: ",
      target_str(task.target_artifact_id),
      "\n",
      "- params: ",
      inspect_compact(task.params),
      "\n",
      "- acceptance_criteria:\n",
      render_criteria(task.acceptance_criteria),
      "\n"
    ]
  end

  defp target_str(nil), do: "nil"
  defp target_str(id) when is_binary(id), do: id

  defp render_criteria(nil), do: "  - (none)\n"
  defp render_criteria([]), do: "  - (none)\n"

  defp render_criteria(criteria) when is_list(criteria) do
    Enum.map(criteria, fn c -> ["  - ", to_string(c), "\n"] end)
  end

  defp inspect_compact(map) when is_map(map) do
    inspect(map, limit: :infinity, printable_limit: :infinity, charlists: :as_lists)
  end

  defp inspect_compact(other), do: inspect(other)
end
