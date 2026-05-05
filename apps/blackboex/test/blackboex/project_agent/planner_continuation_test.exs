defmodule Blackboex.ProjectAgent.PlannerContinuationTest do
  @moduledoc """
  Tests for `Planner.build_plan/2` continuation support: passing a
  `:prior_partial_summary` includes the parent plan's failure context as
  a volatile-segment block so the LLM can re-plan around the failure.
  """

  use Blackboex.DataCase, async: false

  alias Blackboex.ProjectAgent.Planner
  alias Blackboex.ProjectAgent.ProjectIndex

  setup [:create_user_and_org, :create_project]

  setup do
    ProjectIndex.flush_cache()

    on_exit(fn -> Application.delete_env(:blackboex, :project_planner_client) end)
    :ok
  end

  describe "build_plan/2 with :prior_partial_summary" do
    test "passes prior_partial_summary into the volatile segment", ctx do
      received = self()

      Application.put_env(:blackboex, :project_planner_client, fn _project, prompt ->
        send(received, {:prompt_messages, prompt.messages})

        {:ok,
         %{
           title: "Continuation plan",
           tasks: [
             %{
               artifact_type: "api",
               action: "create",
               title: "Re-do failing API",
               params: %{},
               acceptance_criteria: []
             }
           ]
         }}
      end)

      summary = "Prior plan halted at task 2: API compile failed (missing import)"

      assert {:ok, _} =
               Planner.build_plan(ctx.project, %{
                 user_message: "fix the api",
                 prior_partial_summary: summary
               })

      assert_receive {:prompt_messages, messages}

      volatile_texts =
        messages
        |> Enum.reject(&Map.has_key?(&1, :cache_control))
        |> Enum.map(& &1.text)
        |> Enum.join("\n")

      assert volatile_texts =~ summary
    end

    test "omits the prior summary block when not provided", ctx do
      received = self()

      Application.put_env(:blackboex, :project_planner_client, fn _project, prompt ->
        send(received, {:prompt_messages, prompt.messages})

        {:ok,
         %{
           title: "Plan",
           tasks: [
             %{
               artifact_type: "api",
               action: "create",
               title: "x",
               params: %{},
               acceptance_criteria: []
             }
           ]
         }}
      end)

      assert {:ok, _} = Planner.build_plan(ctx.project, %{user_message: "do x"})

      assert_receive {:prompt_messages, messages}

      volatile_texts =
        messages
        |> Enum.reject(&Map.has_key?(&1, :cache_control))
        |> Enum.map(& &1.text)
        |> Enum.join("\n")

      refute volatile_texts =~ "Prior plan"
    end

    test "build_prompt/3 accepts prior_partial_summary and renders it as volatile-segment text",
         ctx do
      summary = "Prior failure: task 3 (page) returned compile error E1"

      result =
        Planner.build_prompt(ctx.project, "continue please", prior_partial_summary: summary)

      volatile_texts =
        result.messages
        |> Enum.reject(&Map.has_key?(&1, :cache_control))
        |> Enum.map(& &1.text)
        |> Enum.join("\n")

      assert volatile_texts =~ summary
      assert volatile_texts =~ "continue please"
    end
  end
end
