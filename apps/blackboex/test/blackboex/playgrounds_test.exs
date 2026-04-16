defmodule Blackboex.PlaygroundsTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Playgrounds
  alias Blackboex.Playgrounds.Playground

  setup [:create_user_and_org]

  describe "create_playground/1" do
    setup [:create_project]

    test "creates a playground with valid attrs", %{org: org, project: project, user: user} do
      attrs = %{
        name: "My Elixir REPL",
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:ok, %Playground{} = pg} = Playgrounds.create_playground(attrs)
      assert pg.name == "My Elixir REPL"
      assert pg.code == ""
      assert pg.last_output == nil
      assert pg.project_id == project.id
      assert pg.slug =~ ~r/^my-elixir-repl-[a-z0-9]{6}$/
    end

    test "fails without required fields" do
      assert {:error, changeset} = Playgrounds.create_playground(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates code max length", %{org: org, project: project, user: user} do
      attrs = %{
        name: "Big Code",
        code: String.duplicate("a", 262_145),
        organization_id: org.id,
        project_id: project.id,
        user_id: user.id
      }

      assert {:error, changeset} = Playgrounds.create_playground(attrs)
      assert %{code: [msg]} = errors_on(changeset)
      assert msg =~ "should be at most"
    end

    test "enforces unique slug per project", %{org: org, project: project, user: user} do
      pg = playground_fixture(%{user: user, org: org, project: project, name: "My Playground"})

      attrs = %{
        name: "Another Playground",
        slug: pg.slug,
        organization_id: org.id,
        project_id: project.id,
        user_id: pg.user_id
      }

      assert {:error, changeset} = Playgrounds.create_playground(attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_playgrounds/1" do
    setup [:create_project]

    test "returns playgrounds for a project", %{user: user, org: org, project: project} do
      pg = playground_fixture(%{user: user, org: org, project: project})

      assert [found] = Playgrounds.list_playgrounds(project.id)
      assert found.id == pg.id
    end

    test "does not return playgrounds from other projects", %{
      user: user,
      org: org,
      project: project
    } do
      other_project = project_fixture(%{user: user, org: org, name: "Other Project"})
      _pg = playground_fixture(%{user: user, org: org, project: project})

      assert [] = Playgrounds.list_playgrounds(other_project.id)
    end
  end

  describe "get_playground/2" do
    test "returns the playground for a project" do
      pg = playground_fixture()
      assert found = Playgrounds.get_playground(pg.project_id, pg.id)
      assert found.id == pg.id
    end

    test "returns nil for wrong project" do
      pg = playground_fixture()
      assert nil == Playgrounds.get_playground(Ecto.UUID.generate(), pg.id)
    end
  end

  describe "get_playground_by_slug/2" do
    test "returns the playground by slug" do
      pg = playground_fixture()
      assert found = Playgrounds.get_playground_by_slug(pg.project_id, pg.slug)
      assert found.id == pg.id
    end
  end

  describe "update_playground/2" do
    test "updates name and code" do
      pg = playground_fixture()

      assert {:ok, updated} =
               Playgrounds.update_playground(pg, %{name: "Updated", code: "IO.puts(:hello)"})

      assert updated.name == "Updated"
      assert updated.code == "IO.puts(:hello)"
    end

    test "slug is immutable on update" do
      pg = playground_fixture()
      original_slug = pg.slug

      assert {:ok, updated} = Playgrounds.update_playground(pg, %{name: "New Name"})
      assert updated.slug == original_slug
    end
  end

  describe "delete_playground/1" do
    test "deletes the playground" do
      pg = playground_fixture()
      assert {:ok, %Playground{}} = Playgrounds.delete_playground(pg)
      assert nil == Playgrounds.get_playground(pg.project_id, pg.id)
    end
  end

  describe "change_playground/2" do
    test "returns a changeset" do
      pg = playground_fixture()
      assert %Ecto.Changeset{} = Playgrounds.change_playground(pg)
    end
  end

  # ── Execution History ─────────────────────────────────────

  describe "create_execution/2" do
    test "creates an execution with run_number 1 for first run" do
      pg = playground_fixture()
      assert {:ok, exec} = Playgrounds.create_execution(pg, "IO.puts(:hello)")
      assert exec.run_number == 1
      assert exec.code_snapshot == "IO.puts(:hello)"
      assert exec.status == "running"
      assert exec.playground_id == pg.id
    end

    test "increments run_number for subsequent runs" do
      pg = playground_fixture()
      {:ok, _exec1} = Playgrounds.create_execution(pg, "1 + 1")
      {:ok, exec2} = Playgrounds.create_execution(pg, "2 + 2")
      {:ok, exec3} = Playgrounds.create_execution(pg, "3 + 3")

      assert exec2.run_number == 2
      assert exec3.run_number == 3
    end
  end

  describe "complete_execution/4" do
    test "updates execution with output, status and duration" do
      pg = playground_fixture()
      {:ok, exec} = Playgrounds.create_execution(pg, "IO.puts(:ok)")

      assert {:ok, completed} = Playgrounds.complete_execution(exec, "ok\n", "success", 150)
      assert completed.output == "ok\n"
      assert completed.status == "success"
      assert completed.duration_ms == 150
    end

    test "marks execution as error" do
      pg = playground_fixture()
      {:ok, exec} = Playgrounds.create_execution(pg, "bad code")

      assert {:ok, completed} =
               Playgrounds.complete_execution(exec, "** (SyntaxError)", "error", 5)

      assert completed.status == "error"
    end
  end

  describe "list_executions/1" do
    test "returns executions ordered by most recent first" do
      pg = playground_fixture()
      {:ok, exec1} = Playgrounds.create_execution(pg, "1")
      {:ok, exec2} = Playgrounds.create_execution(pg, "2")

      executions = Playgrounds.list_executions(pg.id)
      assert length(executions) == 2
      assert hd(executions).id == exec2.id
      assert List.last(executions).id == exec1.id
    end

    test "returns empty list for playground with no executions" do
      pg = playground_fixture()
      assert [] = Playgrounds.list_executions(pg.id)
    end
  end

  describe "get_execution/1" do
    test "returns the execution" do
      pg = playground_fixture()
      {:ok, exec} = Playgrounds.create_execution(pg, "1 + 1")
      assert found = Playgrounds.get_execution(exec.id)
      assert found.id == exec.id
    end

    test "returns nil for unknown id" do
      assert nil == Playgrounds.get_execution(Ecto.UUID.generate())
    end
  end

  describe "cleanup_old_executions/1" do
    test "deletes executions beyond retention limit" do
      pg = playground_fixture()

      # Create 52 executions (beyond the default 50 retention)
      for i <- 1..52 do
        {:ok, exec} = Playgrounds.create_execution(pg, "run #{i}")
        Playgrounds.complete_execution(exec, "out", "success", 10)
      end

      assert {2, _} = Playgrounds.cleanup_old_executions(pg.id)
      assert length(Playgrounds.list_executions(pg.id)) == 50
    end
  end
end
