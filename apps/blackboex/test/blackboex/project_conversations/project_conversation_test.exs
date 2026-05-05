defmodule Blackboex.ProjectConversations.ProjectConversationTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.ProjectConversations.ProjectConversation

  setup do
    {user, org} = user_and_org_fixture()
    project = project_fixture(%{user: user, org: org})
    %{user: user, org: org, project: project}
  end

  defp valid_attrs(%{project: project, org: org}) do
    %{
      project_id: project.id,
      organization_id: org.id,
      status: "active"
    }
  end

  describe "valid_statuses/0" do
    test "returns expected list" do
      assert ProjectConversation.valid_statuses() == ~w(active archived)
    end
  end

  describe "changeset/2" do
    test "valid with all required fields", ctx do
      changeset = ProjectConversation.changeset(%ProjectConversation{}, valid_attrs(ctx))
      assert changeset.valid?
    end

    test "invalid when missing project_id", ctx do
      attrs = Map.delete(valid_attrs(ctx), :project_id)
      changeset = ProjectConversation.changeset(%ProjectConversation{}, attrs)
      refute changeset.valid?
      assert %{project_id: [_]} = errors_on(changeset)
    end

    test "rejects invalid status", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "bogus")
      changeset = ProjectConversation.changeset(%ProjectConversation{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "only one active conversation per project_id", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _} =
               %ProjectConversation{}
               |> ProjectConversation.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %ProjectConversation{}
               |> ProjectConversation.changeset(attrs)
               |> Repo.insert()

      refute changeset.valid?
      assert %{project_id: [_]} = errors_on(changeset)
    end
  end

  describe "archive_changeset/1" do
    test "sets status to archived and archived_at", ctx do
      {:ok, conv} =
        %ProjectConversation{}
        |> ProjectConversation.changeset(valid_attrs(ctx))
        |> Repo.insert()

      changeset = ProjectConversation.archive_changeset(conv)

      assert get_change(changeset, :status) == "archived"
      assert %DateTime{} = get_change(changeset, :archived_at)
    end
  end

  describe "stats_changeset/2" do
    test "accepts non-negative stats", ctx do
      {:ok, conv} =
        %ProjectConversation{}
        |> ProjectConversation.changeset(valid_attrs(ctx))
        |> Repo.insert()

      changeset =
        ProjectConversation.stats_changeset(conv, %{
          total_runs: 3,
          total_events: 12,
          total_input_tokens: 500,
          total_output_tokens: 800,
          total_cost_cents: 7
        })

      assert changeset.valid?
    end

    test "rejects negative totals", ctx do
      {:ok, conv} =
        %ProjectConversation{}
        |> ProjectConversation.changeset(valid_attrs(ctx))
        |> Repo.insert()

      changeset = ProjectConversation.stats_changeset(conv, %{total_runs: -1})
      refute changeset.valid?
      assert %{total_runs: [_]} = errors_on(changeset)
    end
  end

  describe "fixture sanity" do
    test "project_conversation_fixture inserts a row", ctx do
      conv = project_conversation_fixture(%{project: ctx.project})
      assert conv.id
      assert conv.status == "active"
      assert conv.project_id == ctx.project.id
    end
  end
end
