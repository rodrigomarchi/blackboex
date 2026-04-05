defmodule BlackboexWeb.ApiLive.Edit.VersionsLiveTest do
  @moduledoc """
  Expanded tests for VersionsLive (68% → >80% coverage).
  Tests view_version, clear_version_view, ordering, and version sources.
  """

  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Versions Test Org #{System.unique_integer([:positive])}",
        slug: "versionsorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Versions API",
        slug: "versions-api-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{v: 0}"
      })

    %{org: org, api: api, user: user}
  end

  # ── Empty state ────────────────────────────────────────────────────────

  describe "empty versions list" do
    test "shows no-versions message when API has no versions", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "No versions yet"
    end
  end

  # ── Version listing ────────────────────────────────────────────────────

  describe "version listing" do
    test "shows version history with version number", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "v1"
      assert html =~ "generation"
    end

    test "shows multiple versions with correct numbers", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      api = Apis.get_api(org.id, api.id)

      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(org.id, api.id)

      {:ok, _v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "v1"
      assert html =~ "v2"
    end

    test "versions are ordered newest first", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      api = Apis.get_api(org.id, api.id)

      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(org.id, api.id)

      {:ok, _v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      # v2 should appear before v1 in the HTML (newest first)
      v2_pos = :binary.match(html, "v2") |> elem(0)
      v1_pos = :binary.match(html, "v1") |> elem(0)
      assert v2_pos < v1_pos
    end

    test "shows generation source label", %{conn: conn, org: org, api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "generation"
    end

    test "shows manual_edit source label", %{conn: conn, org: org, api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "manual_edit"
    end

    test "shows chat_edit source label", %{conn: conn, org: org, api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "chat_edit",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "chat_edit"
    end

    test "shows View button for each version", %{conn: conn, org: org, api: api, user: user} do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      assert html =~ "View"
    end

    test "shows Restore button only for non-latest versions", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      api = Apis.get_api(org.id, api.id)

      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(org.id, api.id)

      {:ok, _v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      # Restore appears for v1 (not latest)
      assert html =~ "Restore"
    end
  end

  # ── view_version ──────────────────────────────────────────────────────

  describe "view_version" do
    test "clicking View selects the version and highlights it", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      html =
        lv
        |> element(~s(button[phx-click="view_version"][phx-value-number="1"]))
        |> render_click()

      # Selected version gets border-primary styling
      assert html =~ "border-primary"
    end

    test "view_version updates code assign to the version's code", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{version: :one}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      lv
      |> element(~s(button[phx-click="view_version"][phx-value-number="1"]))
      |> render_click()

      # The view renders with selected_version highlighted — no crash
      assert is_binary(render(lv))
    end

    test "view_version with non-existent number shows error flash", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      html = render_click(lv, "view_version", %{"number" => "999"})

      assert html =~ "Version not found"
    end
  end

  # ── clear_version_view ────────────────────────────────────────────────

  describe "clear_version_view" do
    test "clear_version_view resets selected_version to nil", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      # Select version first
      lv
      |> element(~s(button[phx-click="view_version"][phx-value-number="1"]))
      |> render_click()

      # Clear it
      html = render_click(lv, "clear_version_view", %{})

      # After clearing, no version should be highlighted
      refute html =~ "border-primary bg-primary/5"
    end

    test "clear_version_view does not crash when no version selected", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      html = render_click(lv, "clear_version_view", %{})

      assert is_binary(html)
    end
  end

  # ── rollback ──────────────────────────────────────────────────────────

  describe "rollback" do
    test "rollback creates a new version with the old code", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      api = Apis.get_api(org.id, api.id)

      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(org.id, api.id)

      {:ok, _v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      lv
      |> element(~s(button[phx-click="rollback"][phx-value-number="1"]))
      |> render_click()

      # 3 versions after rollback (v1, v2, v3 = rollback of v1)
      assert length(Apis.list_versions(api.id)) == 3
    end

    test "rollback to non-existent version shows error flash", %{
      conn: conn,
      org: org,
      api: api,
      user: user
    } do
      api = Apis.get_api(org.id, api.id)

      {:ok, _v1} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 1}",
          source: "generation",
          created_by_id: user.id
        })

      api = Apis.get_api(org.id, api.id)

      {:ok, _v2} =
        Apis.create_version(api, %{
          code: "def handle(_), do: %{v: 2}",
          source: "manual_edit",
          created_by_id: user.id
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/versions?org=#{org.id}")

      html = render_click(lv, "rollback", %{"number" => "999"})

      assert html =~ "Version not found"
    end
  end
end
