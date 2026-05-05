defmodule Blackboex.ProjectAgent.ProjectIndexTest do
  @moduledoc """
  Tests for the lightweight metadata-only project index used as a stable
  prompt-cache prefix by the Planner. Cache key is
  `(project_id, max_artifact_updated_at)` so artifact mutations
  auto-invalidate.
  """

  use Blackboex.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Blackboex.ProjectAgent.ProjectIndex

  setup [:create_user_and_org, :create_project]

  setup do
    ProjectIndex.flush_cache()
    :ok
  end

  describe "build/1" do
    test "returns an empty digest for a project with no artifacts", %{project: project} do
      digest = ProjectIndex.build(project)

      assert digest.project_id == project.id
      assert digest.apis == []
      assert digest.flows == []
      assert digest.pages == []
      assert digest.playgrounds == []
      assert is_binary(digest.cache_key)
    end

    test "lists APIs in the project (metadata only)", ctx do
      api = api_fixture(Map.merge(Map.take(ctx, [:user, :org, :project]), %{name: "Posts CRUD"}))

      digest = ProjectIndex.build(ctx.project)

      assert [%{id: id, name: "Posts CRUD"}] = digest.apis
      assert id == api.id
    end

    test "lists flows in the project (metadata only)", ctx do
      flow =
        flow_fixture(Map.merge(Map.take(ctx, [:user, :org, :project]), %{name: "Onboarding"}))

      digest = ProjectIndex.build(ctx.project)

      assert [%{id: id, name: "Onboarding"}] = digest.flows
      assert id == flow.id
    end

    test "lists pages and playgrounds", ctx do
      base = Map.take(ctx, [:user, :org, :project])
      _page = page_fixture(Map.merge(base, %{title: "Roadmap"}))
      _playground = playground_fixture(Map.merge(base, %{name: "Snippet"}))

      digest = ProjectIndex.build(ctx.project)

      assert [%{name: "Roadmap"}] = digest.pages
      assert [%{name: "Snippet"}] = digest.playgrounds
    end

    test "cache_key changes when an artifact's updated_at advances", ctx do
      api = api_fixture(Map.merge(Map.take(ctx, [:user, :org, :project]), %{name: "First"}))
      first = ProjectIndex.build(ctx.project).cache_key

      # Force a later updated_at via direct UPDATE; bumping updated_at via
      # the changeset depends on second-precision timestamps which may
      # collide with the insert timestamp inside a single test.
      future = NaiveDateTime.add(api.updated_at, 60, :second)

      Blackboex.Repo.update_all(
        from(a in Blackboex.Apis.Api, where: a.id == ^api.id),
        set: [updated_at: future]
      )

      ProjectIndex.flush_cache()
      second = ProjectIndex.build(ctx.project).cache_key

      refute first == second
    end
  end

  describe "to_text/1" do
    test "renders a stable plain-text digest suitable for cache_control", ctx do
      base = Map.take(ctx, [:user, :org, :project])
      _api = api_fixture(Map.merge(base, %{name: "API One"}))
      _flow = flow_fixture(Map.merge(base, %{name: "Flow One"}))

      text = ctx.project |> ProjectIndex.build() |> ProjectIndex.to_text()

      assert text =~ "Project ID: #{ctx.project.id}"
      assert text =~ "API One"
      assert text =~ "Flow One"
    end
  end

  describe "ETS cache" do
    test "second build/1 with no mutation returns the same struct (cached)", ctx do
      _api = api_fixture(Map.merge(Map.take(ctx, [:user, :org, :project]), %{name: "Cached"}))

      first = ProjectIndex.build(ctx.project)
      second = ProjectIndex.build(ctx.project)

      assert first == second
      assert first.cache_key == second.cache_key
    end
  end
end
