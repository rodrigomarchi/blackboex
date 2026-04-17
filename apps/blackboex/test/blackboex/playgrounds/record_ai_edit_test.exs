defmodule Blackboex.Playgrounds.RecordAiEditTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Playgrounds
  alias Blackboex.Playgrounds.Playground
  alias Blackboex.Playgrounds.PlaygroundExecution

  setup [:create_user_and_org]

  describe "record_ai_edit/3" do
    test "creates an ai_snapshot execution and updates playground.code atomically",
         %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      {:ok, pg} = Playgrounds.update_playground(pg, %{code: "old"})

      assert {:ok, %{playground: %Playground{} = updated, snapshot: snapshot}} =
               Playgrounds.record_ai_edit(pg, "new", "old")

      assert updated.code == "new"
      assert %PlaygroundExecution{} = snapshot
      assert snapshot.status == "ai_snapshot"
      assert snapshot.code_snapshot == "old"
      assert snapshot.playground_id == pg.id
      assert snapshot.run_number == 1
    end

    test "increments run_number for subsequent snapshots", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})

      {:ok, _} = Playgrounds.record_ai_edit(pg, "v1", "")
      pg = Playgrounds.get_playground(pg.project_id, pg.id)
      {:ok, %{snapshot: s2}} = Playgrounds.record_ai_edit(pg, "v2", "v1")

      assert s2.run_number == 2
      assert s2.code_snapshot == "v1"
    end

    test "snapshots appear in execution list", %{user: user, org: org} do
      pg = playground_fixture(%{user: user, org: org})
      {:ok, _} = Playgrounds.record_ai_edit(pg, "hello", "")

      [snap] = Playgrounds.list_executions(pg.id)
      assert snap.status == "ai_snapshot"
      assert snap.code_snapshot == ""
    end
  end
end
