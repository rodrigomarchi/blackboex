defmodule Blackboex.ProjectConversations.ProjectRunTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.ProjectConversations.ProjectConversation
  alias Blackboex.ProjectConversations.ProjectRun

  setup do
    {user, org} = user_and_org_fixture()
    project = project_fixture(%{user: user, org: org})

    {:ok, conversation} =
      %ProjectConversation{}
      |> ProjectConversation.changeset(%{
        project_id: project.id,
        organization_id: org.id,
        status: "active"
      })
      |> Repo.insert()

    %{user: user, org: org, project: project, conversation: conversation}
  end

  defp valid_attrs(%{user: user, org: org, project: project, conversation: conversation}) do
    %{
      conversation_id: conversation.id,
      project_id: project.id,
      organization_id: org.id,
      user_id: user.id,
      run_type: "plan",
      status: "pending",
      trigger_message: "build a CRUD"
    }
  end

  describe "valid_run_types/0" do
    test "returns expected list" do
      assert ProjectRun.valid_run_types() == ~w(plan execute)
    end
  end

  describe "valid_statuses/0" do
    test "returns expected list" do
      assert ProjectRun.valid_statuses() == ~w(pending running completed failed canceled)
    end
  end

  describe "changeset/2" do
    test "valid with all required fields", ctx do
      changeset = ProjectRun.changeset(%ProjectRun{}, valid_attrs(ctx))
      assert changeset.valid?
    end

    test "rejects unknown run_type", ctx do
      attrs = Map.put(valid_attrs(ctx), :run_type, "bogus")
      changeset = ProjectRun.changeset(%ProjectRun{}, attrs)
      refute changeset.valid?
      assert %{run_type: [_]} = errors_on(changeset)
    end

    test "rejects unknown status", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "bogus")
      changeset = ProjectRun.changeset(%ProjectRun{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "missing required fields produces errors" do
      changeset = ProjectRun.changeset(%ProjectRun{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :conversation_id)
      assert Map.has_key?(errors, :project_id)
      assert Map.has_key?(errors, :organization_id)
      assert Map.has_key?(errors, :user_id)
      assert Map.has_key?(errors, :run_type)
    end
  end

  describe "running_changeset/2" do
    test "sets status running and started_at" do
      now = DateTime.utc_now()

      changeset =
        ProjectRun.running_changeset(%ProjectRun{}, %{status: "running", started_at: now})

      assert get_change(changeset, :status) == "running"
      assert get_change(changeset, :started_at) == now
    end
  end

  describe "completion_changeset/2" do
    test "completed: persists status, run_summary, tokens" do
      now = DateTime.utc_now()

      attrs = %{
        status: "completed",
        run_summary: "all tasks done",
        input_tokens: 100,
        output_tokens: 200,
        cost_cents: 1,
        completed_at: now,
        duration_ms: 1234
      }

      changeset = ProjectRun.completion_changeset(%ProjectRun{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == "completed"
      assert get_change(changeset, :run_summary) == "all tasks done"
    end

    test "failed: persists error_message" do
      attrs = %{
        status: "failed",
        error_message: "boom",
        completed_at: DateTime.utc_now()
      }

      changeset = ProjectRun.completion_changeset(%ProjectRun{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == "failed"
      assert get_change(changeset, :error_message) == "boom"
    end

    test "rejects negative tokens" do
      changeset = ProjectRun.completion_changeset(%ProjectRun{}, %{input_tokens: -1})
      refute changeset.valid?
      assert %{input_tokens: [_]} = errors_on(changeset)
    end
  end

  describe "fixture sanity" do
    test "project_run_fixture inserts a row", ctx do
      run = project_run_fixture(%{conversation: ctx.conversation, user: ctx.user})
      assert run.id
      assert run.status == "pending"
      assert run.run_type == "plan"
    end
  end
end
