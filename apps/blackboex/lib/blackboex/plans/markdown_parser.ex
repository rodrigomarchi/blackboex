defmodule Blackboex.Plans.MarkdownParser do
  @moduledoc """
  Parses the (possibly user-edited) markdown body of a `Plan` and validates
  that the user's edits respect the plan's invariants.

  Allowed user edits:

    * `acceptance_criteria` text (any number of bullets)
    * `params` map content (within the structural keys)
    * task `title`
    * Reordering tasks (the parser re-numbers `order` from the new
      sequence). v1 tracks but does NOT emit `:order_changed` violations
      since dependencies are not yet first-class.

  Forbidden edits (each emits a `violation/0`):

    * Renaming required keys (`artifact_type`, `action`,
      `target_artifact_id`, `params`, `acceptance_criteria`,
      `- ` bullet structure) → `:structural_field_renamed`
    * Setting `artifact_type` to a value outside
      `Blackboex.Plans.PlanTask.valid_artifact_types/0` →
      `:invalid_artifact_type`
    * Setting `action` to a value outside `valid_actions/0` →
      `:invalid_action`
    * Changing `target_artifact_id` for an `edit` task →
      `:target_artifact_changed`

  Output on success:

      {:ok, %{title: String.t(), tasks: [parsed_task()]}}

  where `parsed_task()` carries the structural fields plus the freely
  editable `title`, `params`, and `acceptance_criteria`.
  """

  alias Blackboex.Plans.{Plan, PlanTask}

  @type violation ::
          {:invalid_artifact_type, integer()}
          | {:invalid_action, integer()}
          | {:order_changed, integer()}
          | {:target_artifact_changed, integer()}
          | {:structural_field_renamed, atom()}

  @type parsed_task :: %{
          order: non_neg_integer(),
          artifact_type: String.t(),
          action: String.t(),
          target_artifact_id: String.t() | nil,
          title: String.t(),
          params: map(),
          acceptance_criteria: [String.t()]
        }

  @valid_artifact_types PlanTask.valid_artifact_types()
  @valid_actions PlanTask.valid_actions()

  # The required structural keys (renaming any of these is a violation).
  @required_keys [:artifact_type, :action, :target_artifact_id, :params, :acceptance_criteria]

  @key_lookup %{
    "artifact_type" => :artifact_type,
    "action" => :action,
    "target_artifact_id" => :target_artifact_id,
    "params" => :params,
    "acceptance_criteria" => :acceptance_criteria
  }

  @spec parse_and_validate(String.t(), Plan.t()) ::
          {:ok, %{title: String.t(), tasks: [parsed_task()]}}
          | {:error, [violation()]}
  def parse_and_validate(markdown, %Plan{} = plan) when is_binary(markdown) do
    lines = String.split(markdown, ~r/\r\n|\n/)

    with {:ok, title, rest} <- parse_title(lines),
         {:ok, raw_tasks} <- split_tasks(rest) do
      {parsed_tasks, structural_violations} = parse_tasks(raw_tasks)

      domain_violations = validate_tasks(parsed_tasks, plan)

      case structural_violations ++ domain_violations do
        [] -> {:ok, %{title: title, tasks: parsed_tasks}}
        violations -> {:error, violations}
      end
    else
      {:error, violation} -> {:error, [violation]}
    end
  end

  # ── Title ──────────────────────────────────────────────────────

  defp parse_title([]), do: {:error, {:structural_field_renamed, :title}}

  defp parse_title(lines) do
    case Enum.split_while(lines, fn line -> not String.starts_with?(line, "# ") end) do
      {_pre, ["# " <> title | rest]} ->
        {:ok, String.trim(title), rest}

      _ ->
        {:error, {:structural_field_renamed, :title}}
    end
  end

  # ── Splitting tasks by `## N.` headers ─────────────────────────

  defp split_tasks(lines) do
    tasks =
      lines
      |> Enum.reduce([], &fold_task_line/2)
      |> Enum.reverse()
      |> Enum.map(fn {header, body} -> {header, Enum.reverse(body)} end)

    {:ok, tasks}
  end

  defp fold_task_line(line, acc) do
    if Regex.match?(~r/^## \d+\./, line) do
      [{line, []} | acc]
    else
      append_to_current_task(line, acc)
    end
  end

  defp append_to_current_task(line, [{header, body} | rest]),
    do: [{header, [line | body]} | rest]

  defp append_to_current_task(_line, []), do: []

  # ── Per-task parsing ───────────────────────────────────────────

  defp parse_tasks(raw_tasks) do
    raw_tasks
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {{header, body}, idx}, {acc_tasks, acc_v} ->
      case parse_task(header, body, idx) do
        {:ok, task} -> {[task | acc_tasks], acc_v}
        {:error, viols} -> {acc_tasks, viols ++ acc_v}
      end
    end)
    |> then(fn {tasks, viols} -> {Enum.reverse(tasks), Enum.reverse(viols)} end)
  end

  defp parse_task(header, body, order) do
    title = parse_task_title(header)
    bullets = collect_bullets(body)

    case extract_required(bullets) do
      {:ok, structural} ->
        criteria = parse_criteria(body)

        {:ok,
         %{
           order: order,
           title: title,
           artifact_type: structural.artifact_type,
           action: structural.action,
           target_artifact_id: parse_target(structural.target_artifact_id),
           params: parse_params(structural.params),
           acceptance_criteria: criteria
         }}

      {:error, viols} ->
        {:error, viols}
    end
  end

  defp parse_task_title(header) do
    case Regex.run(~r/^##\s+\d+\.\s*(.*)$/, header) do
      [_, title] -> String.trim(title)
      _ -> ""
    end
  end

  defp collect_bullets(body_lines) do
    body_lines
    |> Enum.flat_map(&parse_bullet_line/1)
    |> Map.new()
  end

  defp parse_bullet_line(line) do
    case Regex.run(~r/^-\s+([a-z_]+):\s*(.*)$/, line) do
      [_, key, val] -> lookup_bullet_key(key, val)
      _ -> []
    end
  end

  defp lookup_bullet_key(key, val) do
    case Map.fetch(@key_lookup, key) do
      {:ok, atom_key} -> [{atom_key, val}]
      :error -> []
    end
  end

  defp extract_required(bullets) do
    missing =
      Enum.filter(@required_keys, fn key ->
        not Map.has_key?(bullets, key)
      end)

    case missing do
      [] ->
        {:ok,
         %{
           artifact_type: Map.get(bullets, :artifact_type, ""),
           action: Map.get(bullets, :action, ""),
           target_artifact_id: Map.get(bullets, :target_artifact_id, "nil"),
           params: Map.get(bullets, :params, "%{}")
         }}

      [first | _] ->
        {:error, [{:structural_field_renamed, first}]}
    end
  end

  defp parse_target("nil"), do: nil
  defp parse_target(""), do: nil
  defp parse_target(other) when is_binary(other), do: String.trim(other)

  # `params` is rendered as `inspect(map)`. Round-trip via `Code.eval_string/1`.
  # If evaluation raises (user typed garbage), degrade to `%{}` so the parser
  # stays pure and bounded.
  defp parse_params(""), do: %{}
  defp parse_params("%{}"), do: %{}

  defp parse_params(str) when is_binary(str) do
    {result, _} = Code.eval_string(str, [], __ENV__)
    if is_map(result), do: result, else: %{}
  rescue
    _ -> %{}
  end

  defp parse_criteria(body_lines) do
    body_lines
    |> Enum.drop_while(fn line -> not String.starts_with?(line, "- acceptance_criteria:") end)
    |> Enum.drop(1)
    |> Enum.flat_map(&parse_criterion_line/1)
  end

  defp parse_criterion_line(line) do
    case Regex.run(~r/^\s{2,}-\s+(.*)$/, line) do
      [_, val] -> emit_criterion(val)
      _ -> []
    end
  end

  defp emit_criterion(val) do
    trimmed = String.trim(val)
    if trimmed == "" or trimmed == "(none)", do: [], else: [trimmed]
  end

  # ── Domain validation against the original plan ────────────────

  defp validate_tasks(parsed_tasks, %Plan{} = plan) do
    original_tasks = original_tasks_by_order(plan)

    Enum.flat_map(parsed_tasks, fn task ->
      original = Map.get(original_tasks, task.order)

      [
        validate_artifact_type(task),
        validate_action(task),
        validate_target_unchanged(task, original)
      ]
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp original_tasks_by_order(%Plan{tasks: %Ecto.Association.NotLoaded{}}), do: %{}
  defp original_tasks_by_order(%Plan{tasks: nil}), do: %{}

  defp original_tasks_by_order(%Plan{tasks: tasks}) when is_list(tasks) do
    Map.new(tasks, fn t -> {t.order, t} end)
  end

  defp validate_artifact_type(%{artifact_type: at, order: order}) do
    if at in @valid_artifact_types, do: nil, else: {:invalid_artifact_type, order}
  end

  defp validate_action(%{action: a, order: order}) do
    if a in @valid_actions, do: nil, else: {:invalid_action, order}
  end

  defp validate_target_unchanged(
         %{action: "edit", target_artifact_id: parsed_id, order: order},
         %PlanTask{action: "edit", target_artifact_id: original_id}
       )
       when parsed_id != original_id do
    {:target_artifact_changed, order}
  end

  defp validate_target_unchanged(_task, _original), do: nil
end
