defmodule Blackboex.Plans.ConcurrentApprovalTest do
  @moduledoc """
  Verifies the partial-unique-index race wrapping in `Plans.approve_plan/3`.

  True parallelism cannot be observed inside the Ecto SQL sandbox (every
  transaction shares the same outer test transaction, so commit-time
  constraint violations don't fire until rollback). The semantically
  equivalent test sequences two approvals against the same project: the
  second one MUST receive `{:error, :concurrent_active_plan}` even though
  it carries a stale `:draft` snapshot.
  """

  use Blackboex.DataCase, async: true

  alias Blackboex.Plans
  alias Blackboex.Plans.MarkdownRenderer

  setup [:create_user_and_org, :create_project]

  test "second approval for the same project gets {:error, :concurrent_active_plan}",
       %{user: user, project: project} do
    plan_a = plan_fixture(%{project: project})
    _t = plan_task_fixture(%{plan: plan_a, order: 0})
    plan_a = Plans.get_plan!(plan_a.id) |> Repo.preload(:tasks)

    plan_b = plan_fixture(%{project: project})
    _t = plan_task_fixture(%{plan: plan_b, order: 0})
    plan_b = Plans.get_plan!(plan_b.id) |> Repo.preload(:tasks)

    md_a = MarkdownRenderer.render(plan_a)
    md_b = MarkdownRenderer.render(plan_b)

    assert {:ok, %{status: "approved"}} =
             Plans.approve_plan(plan_a, user, %{markdown_body: md_a})

    # Second approval comes in carrying a stale `:draft` snapshot — the
    # in-memory state machine check passes; the partial-unique index
    # rejects the UPDATE; our wrapper translates that to a structured
    # error tuple.
    assert {:error, :concurrent_active_plan} =
             Plans.approve_plan(plan_b, user, %{markdown_body: md_b})
  end

  test "after the active plan terminates, a new one can be approved",
       %{user: user, project: project} do
    plan_a = plan_fixture(%{project: project})
    _t = plan_task_fixture(%{plan: plan_a, order: 0})
    plan_a = Plans.get_plan!(plan_a.id) |> Repo.preload(:tasks)

    plan_b = plan_fixture(%{project: project})
    _t = plan_task_fixture(%{plan: plan_b, order: 0})
    plan_b = Plans.get_plan!(plan_b.id) |> Repo.preload(:tasks)

    md_a = MarkdownRenderer.render(plan_a)
    md_b = MarkdownRenderer.render(plan_b)

    {:ok, plan_a} = Plans.approve_plan(plan_a, user, %{markdown_body: md_a})
    {:ok, plan_a} = Plans.mark_plan_running(plan_a)
    {:ok, _plan_a} = Plans.mark_plan_failed(plan_a, "boom")

    # Active slot is now free (plan_a is :failed). plan_b should approve.
    assert {:ok, %{status: "approved"}} =
             Plans.approve_plan(plan_b, user, %{markdown_body: md_b})
  end
end
