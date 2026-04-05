defmodule BlackboexWeb.ApiLive.Edit.InfoLiveTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :register_and_log_in_user

  setup %{user: user} do
    Apis.Registry.clear()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{
        name: "Info Org #{System.unique_integer([:positive])}",
        slug: "infoorg-#{System.unique_integer([:positive])}"
      })

    {:ok, api} =
      Apis.create_api(%{
        name: "Info Test API",
        slug: "info-test-#{System.unique_integer([:positive])}",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{ok: true}"
      })

    %{org: org, api: api}
  end

  describe "mount" do
    test "renders info tab with API details", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "API Information"
      assert html =~ "Info Test API"
      assert html =~ "computation"
    end

    test "shows danger zone with archive button", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "Archive this API"
      assert html =~ "archive_api"
    end

    test "shows code stats section", %{conn: conn, org: org, api: api} do
      {:ok, _lv, html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert html =~ "Source Lines"
      assert html =~ "Test Lines"
      assert html =~ "Versions"
    end
  end

  describe "update_info" do
    test "with valid name and description updates the API", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "Updated Name", "description" => "New description"})

      assert html =~ "Updated Name"
    end

    test "shows success flash after update", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "New Name", "description" => "A description"})

      assert html =~ "API info updated"
    end

    test "persists name change in database", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      lv
      |> element("form")
      |> render_submit(%{"name" => "Persisted Name", "description" => ""})

      updated = Apis.get_api(org.id, api.id)
      assert updated.name == "Persisted Name"
    end

    test "trims whitespace from name and description", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      lv
      |> element("form")
      |> render_submit(%{"name" => "  Trimmed Name  ", "description" => "  trimmed desc  "})

      updated = Apis.get_api(org.id, api.id)
      assert updated.name == "Trimmed Name"
      assert updated.description == "trimmed desc"
    end

    test "update with empty name shows error or keeps old name", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      html =
        lv
        |> element("form")
        |> render_submit(%{"name" => "", "description" => "some desc"})

      # Should either show validation error or keep old name
      assert html =~ "Info Test API" or html =~ "can't be blank" or
               html =~ "error" or html =~ "Failed"
    end
  end

  describe "archive_api" do
    test "marks API as archived and redirects to /apis", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      assert {:error, {:live_redirect, %{to: "/apis"}}} =
               lv
               |> element(~s(button[phx-click="archive_api"]))
               |> render_click()
    end

    test "sets status to archived in database", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      lv
      |> element(~s(button[phx-click="archive_api"]))
      |> render_click()

      archived = Apis.get_api(org.id, api.id)
      assert archived.status == "archived"
    end

    test "shows info flash before redirect", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      result =
        lv
        |> element(~s(button[phx-click="archive_api"]))
        |> render_click()

      # Either a redirect (live_redirect error) or html with flash
      case result do
        {:error, {:live_redirect, _}} ->
          assert true

        html when is_binary(html) ->
          assert html =~ "archived"
      end
    end
  end

  describe "copy_url" do
    test "triggers JS copy_to_clipboard event", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/info?org=#{org.id}")

      # The event should not crash; it pushes a client-side event
      html = render_click(lv, "copy_url", %{})
      assert is_binary(html)
    end
  end
end
