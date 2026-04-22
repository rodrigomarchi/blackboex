defmodule Blackboex.PageConversations.PageConversationTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.PageConversations.PageConversation

  setup do
    {user, org} = user_and_org_fixture()
    page = page_fixture(%{user: user, org: org})
    %{user: user, org: org, page: page}
  end

  defp valid_attrs(%{page: page, org: org}) do
    %{
      page_id: page.id,
      organization_id: org.id,
      project_id: page.project_id,
      status: "active"
    }
  end

  describe "valid_statuses/0" do
    test "returns expected list" do
      assert PageConversation.valid_statuses() == ~w(active archived)
    end
  end

  describe "changeset/2" do
    test "valid with all required fields", ctx do
      changeset = PageConversation.changeset(%PageConversation{}, valid_attrs(ctx))
      assert changeset.valid?
    end

    test "invalid when missing page_id", ctx do
      attrs = Map.delete(valid_attrs(ctx), :page_id)
      changeset = PageConversation.changeset(%PageConversation{}, attrs)
      refute changeset.valid?
      assert %{page_id: [_]} = errors_on(changeset)
    end

    test "rejects invalid status", ctx do
      attrs = Map.put(valid_attrs(ctx), :status, "bogus")
      changeset = PageConversation.changeset(%PageConversation{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "only one active conversation per page_id", ctx do
      attrs = valid_attrs(ctx)

      assert {:ok, _} =
               %PageConversation{}
               |> PageConversation.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %PageConversation{}
               |> PageConversation.changeset(attrs)
               |> Repo.insert()

      refute changeset.valid?
      assert %{page_id: [_]} = errors_on(changeset)
    end
  end

  describe "archive_changeset/1" do
    test "sets status to archived and archived_at", ctx do
      {:ok, conv} =
        %PageConversation{}
        |> PageConversation.changeset(valid_attrs(ctx))
        |> Repo.insert()

      changeset = PageConversation.archive_changeset(conv)

      assert get_change(changeset, :status) == "archived"
      assert %DateTime{} = get_change(changeset, :archived_at)
    end
  end

  describe "stats_changeset/2" do
    test "accepts non-negative stats", ctx do
      {:ok, conv} =
        %PageConversation{}
        |> PageConversation.changeset(valid_attrs(ctx))
        |> Repo.insert()

      changeset =
        PageConversation.stats_changeset(conv, %{
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
        %PageConversation{}
        |> PageConversation.changeset(valid_attrs(ctx))
        |> Repo.insert()

      changeset = PageConversation.stats_changeset(conv, %{total_runs: -1})
      refute changeset.valid?
      assert %{total_runs: [_]} = errors_on(changeset)
    end
  end
end
