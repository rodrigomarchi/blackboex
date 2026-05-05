defmodule BlackboexWeb.ProjectAgentLiveTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Blackboex.Plans
  alias Blackboex.ProjectEnvVars

  @moduletag :liveview

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, "/orgs/any/projects/any/agent")
    end
  end

  describe "feature flag off" do
    setup :register_and_log_in_user

    setup %{user: user} do
      org = org_fixture(%{user: user})
      project = project_fixture(%{user: user, org: org})
      %{org: org, project: project}
    end

    test "redirects to project root with flash when project_agent disabled", %{
      conn: conn,
      org: org,
      project: project
    } do
      previous = Application.get_env(:blackboex, :features, [])

      try do
        Application.put_env(:blackboex, :features, project_agent: false)

        {:ok, _} =
          ProjectEnvVars.create(%{
            project_id: project.id,
            organization_id: org.id,
            name: "FEATURE_PROJECT_AGENT",
            value: "false"
          })

        path = ~p"/orgs/#{org.slug}/projects/#{project.slug}/agent"

        assert {:error, {:live_redirect, %{to: redirect_to, flash: flash}}} = live(conn, path)
        assert redirect_to == ~p"/orgs/#{org.slug}/projects/#{project.slug}/"
        assert flash["error"] =~ "Project Agent"
      after
        Application.put_env(:blackboex, :features, previous)
      end
    end
  end

  describe "feature flag on, no active plan" do
    setup [:register_and_log_in_user, :stub_llm_client]

    setup %{user: user} do
      org = org_fixture(%{user: user})
      project = project_fixture(%{user: user, org: org})
      %{org: org, project: project}
    end

    defp agent_path(org, project),
      do: ~p"/orgs/#{org.slug}/projects/#{project.slug}/agent"

    test "renders the chat composer in the empty state", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, view, html} = live(conn, agent_path(org, project))
      assert html =~ "Project Agent"

      # New chat-style UI: composer with phx-submit="send_chat" and a
      # placeholder describing the planning step.
      assert_has(view, "form[phx-submit=\"send_chat\"]")
      assert_has(view, "input[name=\"message\"]")
      assert html =~ "Describe what you want to build"
    end

    test "broadcasting :plan_drafted renders the inline plan card with Approve button", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      {:ok, view, _html} = live(conn, agent_path(org, project))

      attrs = %{
        title: "Sample plan",
        user_message: "do something",
        markdown_body:
          "# Sample plan\n\n## Task 1: Do thing\n\n- artifact_type: api\n- action: create\n",
        tasks: [
          %{artifact_type: "api", action: "create", title: "Do thing"}
        ]
      }

      {:ok, plan} = Plans.create_draft_plan(project, user, attrs)

      # Persist a `plan_drafted` event so the chat timeline picks it up
      # the same way the production `KickoffWorker` would.
      _ = persist_plan_drafted_event(plan, user)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:project:#{project.id}",
        {:plan_drafted, plan}
      )

      html = render(view)
      assert_has(view, "[data-role=\"plan-card\"]")
      assert_has(view, "button[phx-click=\"approve_plan\"]")
      assert html =~ "Sample plan"
      assert html =~ "Do thing"
    end

    test "task_completed broadcast renders task_completed event in chat", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      {:ok, view, _html} = live(conn, agent_path(org, project))

      attrs = %{
        title: "Sample plan",
        user_message: "do something",
        markdown_body: "# Sample plan\n",
        tasks: [
          %{artifact_type: "api", action: "create", title: "Do thing"}
        ]
      }

      {:ok, plan} = Plans.create_draft_plan(project, user, attrs)
      run = persist_plan_drafted_event(plan, user)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:project:#{project.id}",
        {:plan_drafted, plan}
      )

      [task] = plan.tasks
      {:ok, running_task} = Plans.mark_task_running(task, Ecto.UUID.generate())
      {:ok, _done_task} = Plans.mark_task_done(running_task)

      # The production caller (BroadcastAdapter.handle_terminal/4)
      # appends a task_completed ProjectEvent. Simulate that here.
      _ =
        Blackboex.ProjectConversations.append_event(run, %{
          event_type: "task_completed",
          content: "Task completed: Do thing",
          metadata: %{"task_id" => task.id}
        })

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:#{plan.id}",
        {:project_task_completed,
         %{plan_id: plan.id, task_id: task.id, status: :completed, error: nil}}
      )

      _ = render(view)
      assert_has(view, "[data-role=\"task-done\"]")
    end

    test "approve_plan flashes error when concurrent plan already running", %{
      conn: conn,
      org: org,
      project: project,
      user: user
    } do
      {:ok, view, _html} = live(conn, agent_path(org, project))

      attrs = %{
        title: "Sample plan",
        user_message: "do something",
        markdown_body: "# Sample plan\n",
        tasks: [
          %{artifact_type: "api", action: "create", title: "Do thing"}
        ]
      }

      {:ok, draft} = Plans.create_draft_plan(project, user, attrs)
      _ = persist_plan_drafted_event(draft, user)

      Phoenix.PubSub.broadcast(
        Blackboex.PubSub,
        "project_plan:project:#{project.id}",
        {:plan_drafted, draft}
      )

      # Sibling approved plan trips the partial-unique constraint.
      _other_active = approved_plan_fixture(%{project: project})

      _ =
        view
        |> element("button[phx-click=\"approve_plan\"]")
        |> render_click()

      rendered = render(view)
      assert rendered =~ "Another plan is already active" or rendered =~ "concurrent"
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp persist_plan_drafted_event(plan, user) do
    project = Blackboex.Repo.get!(Blackboex.Projects.Project, plan.project_id)

    {:ok, conv} =
      Blackboex.ProjectConversations.get_or_create_active_conversation(
        plan.project_id,
        project.organization_id
      )

    {:ok, run} =
      Blackboex.ProjectConversations.create_run(%{
        conversation_id: conv.id,
        project_id: plan.project_id,
        organization_id: project.organization_id,
        user_id: user.id,
        run_type: "plan",
        status: "completed",
        trigger_message: plan.user_message
      })

    _ = Blackboex.Repo.update!(Ecto.Changeset.change(plan, run_id: run.id))

    _ =
      Blackboex.ProjectConversations.append_event(run, %{
        event_type: "user_message",
        content: plan.user_message
      })

    {:ok, _} =
      Blackboex.ProjectConversations.append_event(run, %{
        event_type: "plan_drafted",
        content: plan.title,
        metadata: %{"plan_id" => plan.id}
      })

    run
  end
end
