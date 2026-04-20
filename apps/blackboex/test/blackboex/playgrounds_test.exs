defmodule Blackboex.PlaygroundsTest do
  use Blackboex.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Blackboex.Playgrounds
  alias Blackboex.Playgrounds.Playground
  alias Blackboex.Repo

  setup [:create_user_and_org]

  describe "create_playground/1 ownership" do
    test "rejects cross-org project (T4 IDOR)", %{user: user, org: org_a} do
      org_b = org_fixture(%{user: user})
      project_b = project_fixture(%{user: user, org: org_b})

      count_before = Repo.one(from(p in Playground, select: count(p.id)))

      assert {:error, :forbidden} =
               Playgrounds.create_playground(%{
                 name: "Hack",
                 organization_id: org_a.id,
                 project_id: project_b.id,
                 user_id: user.id
               })

      assert Repo.one(from(p in Playground, select: count(p.id))) == count_before
    end

    test "allows same-org project (T5 happy path)", %{user: user, org: org, project: project} do
      assert {:ok, %Playground{}} =
               Playgrounds.create_playground(%{
                 name: "ok",
                 organization_id: org.id,
                 project_id: project.id,
                 user_id: user.id
               })
    end
  end

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

  describe "list_for_project/2" do
    test "returns only playgrounds belonging to the given project", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "PG Project A"})
      project_b = project_fixture(%{user: user, org: org, name: "PG Project B"})

      _pg1 = playground_fixture(%{user: user, org: org, project: project_a, name: "Alpha PG"})
      _pg2 = playground_fixture(%{user: user, org: org, project: project_a, name: "Beta PG"})
      _pg3 = playground_fixture(%{user: user, org: org, project: project_a, name: "Gamma PG"})
      _pg4 = playground_fixture(%{user: user, org: org, project: project_b, name: "Delta PG"})
      _pg5 = playground_fixture(%{user: user, org: org, project: project_b, name: "Epsilon PG"})

      results_a = Playgrounds.list_for_project(project_a.id)
      results_b = Playgrounds.list_for_project(project_b.id)

      assert length(results_a) == 3
      assert length(results_b) == 2
      assert Enum.all?(results_a, &(&1.project_id == project_a.id))
    end

    test "returns playgrounds ordered by name ASC", %{user: user, org: org} do
      project = project_fixture(%{user: user, org: org, name: "Sorted PGs"})

      playground_fixture(%{user: user, org: org, project: project, name: "Zeta PG"})
      playground_fixture(%{user: user, org: org, project: project, name: "Alpha PG"})
      playground_fixture(%{user: user, org: org, project: project, name: "Mango PG"})

      results = Playgrounds.list_for_project(project.id)
      names = Enum.map(results, & &1.name)

      assert names == Enum.sort(names)
    end

    test "respects :limit option", %{user: user, org: org} do
      project = project_fixture(%{user: user, org: org, name: "Limited PGs"})

      playground_fixture(%{user: user, org: org, project: project, name: "PG One"})
      playground_fixture(%{user: user, org: org, project: project, name: "PG Two"})
      playground_fixture(%{user: user, org: org, project: project, name: "PG Three"})

      results = Playgrounds.list_for_project(project.id, limit: 2)

      assert length(results) == 2
    end
  end

  describe "move_playground/2" do
    test "moves playground to another project in same org", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      project_b = project_fixture(%{user: user, org: org, name: "Dest"})
      pg = playground_fixture(%{user: user, org: org, project: project_a})

      assert {:ok, updated} = Playgrounds.move_playground(pg, project_b.id)
      assert updated.project_id == project_b.id
    end

    test "returns forbidden when destination project belongs to another org", %{
      user: user,
      org: org
    } do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      pg = playground_fixture(%{user: user, org: org, project: project_a})

      other_user = user_fixture()
      other_org = org_fixture(%{user: other_user})
      other_project = project_fixture(%{user: other_user, org: other_org})

      assert {:error, :forbidden} = Playgrounds.move_playground(pg, other_project.id)
      assert Playgrounds.get_playground(project_a.id, pg.id).project_id == project_a.id
    end

    test "returns forbidden when destination project_id does not exist", %{user: user, org: org} do
      project_a = project_fixture(%{user: user, org: org, name: "Source"})
      pg = playground_fixture(%{user: user, org: org, project: project_a})
      nonexistent_id = Ecto.UUID.generate()

      assert {:error, :forbidden} = Playgrounds.move_playground(pg, nonexistent_id)
      assert Playgrounds.get_playground(project_a.id, pg.id).project_id == project_a.id
    end
  end
end
