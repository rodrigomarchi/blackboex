defmodule Blackboex.PageConversations.PageRunTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.PageConversations.PageConversation
  alias Blackboex.PageConversations.PageRun

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})

    {:ok, conversation} =
      %PageConversation{}
      |> PageConversation.changeset(%{
        page_id: page.id,
        organization_id: org.id,
        project_id: page.project_id,
        status: "active"
      })
      |> Repo.insert()

    %{user: user, org: org, page: page, conversation: conversation}
  end

  defp valid_attrs(%{user: user, org: org, page: page, conversation: conversation}) do
    %{
      conversation_id: conversation.id,
      page_id: page.id,
      organization_id: org.id,
      user_id: user.id,
      run_type: "edit",
      status: "pending",
      trigger_message: "Edit my page"
    }
  end

  describe "valid_run_types/0" do
    test "returns expected list" do
      assert PageRun.valid_run_types() == ~w(generate edit)
    end
  end

  describe "valid_statuses/0" do
    test "returns expected list" do
      assert PageRun.valid_statuses() == ~w(pending running completed failed canceled)
    end
  end

  describe "changeset/2" do
    test "valid with all required fields", ctx do
      changeset = PageRun.changeset(%PageRun{}, valid_attrs(ctx))
      assert changeset.valid?
    end

    test "rejects unknown run_type", ctx do
      attrs = Map.put(valid_attrs(ctx), :run_type, "bogus")
      changeset = PageRun.changeset(%PageRun{}, attrs)
      refute changeset.valid?
      assert %{run_type: [_]} = errors_on(changeset)
    end

    test "rejects unknown status", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "bogus")
      changeset = PageRun.changeset(%PageRun{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "missing required fields produces errors" do
      changeset = PageRun.changeset(%PageRun{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :conversation_id)
      assert Map.has_key?(errors, :page_id)
      assert Map.has_key?(errors, :organization_id)
      assert Map.has_key?(errors, :user_id)
      assert Map.has_key?(errors, :run_type)
    end
  end

  describe "running_changeset/2" do
    test "sets status running and started_at" do
      now = DateTime.utc_now()
      changeset = PageRun.running_changeset(%PageRun{}, %{status: "running", started_at: now})
      assert get_change(changeset, :status) == "running"
      assert get_change(changeset, :started_at) == now
    end
  end

  describe "completion_changeset/2" do
    test "completed: persists status, content_after, run_summary, tokens" do
      now = DateTime.utc_now()

      attrs = %{
        status: "completed",
        content_after: "# Hello",
        run_summary: "wrote intro",
        input_tokens: 100,
        output_tokens: 200,
        cost_cents: 1,
        completed_at: now,
        duration_ms: 1234
      }

      changeset = PageRun.completion_changeset(%PageRun{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == "completed"
      assert get_change(changeset, :content_after) == "# Hello"
      assert get_change(changeset, :input_tokens) == 100
    end

    test "failed: persists error_message" do
      attrs = %{
        status: "failed",
        error_message: "boom",
        completed_at: DateTime.utc_now()
      }

      changeset = PageRun.completion_changeset(%PageRun{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :status) == "failed"
      assert get_change(changeset, :error_message) == "boom"
    end

    test "rejects negative tokens" do
      changeset = PageRun.completion_changeset(%PageRun{}, %{input_tokens: -1})
      refute changeset.valid?
      assert %{input_tokens: [_]} = errors_on(changeset)
    end
  end
end
