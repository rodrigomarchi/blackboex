defmodule BlackboexWeb.DashboardLiveTest do
  use BlackboexWeb.ConnCase, async: true

  alias Blackboex.Apis
  alias Blackboex.Organizations

  @moduletag :liveview

  describe "unauthenticated user" do
    test "redirects to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/dashboard")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end

  describe "authenticated user with no APIs" do
    setup :register_and_log_in_user

    test "renders dashboard page title", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"
    end

    test "shows welcome empty state when no APIs exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Welcome to BlackBoex"
    end

    test "shows create first API button in empty state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Create your first API"
    end
  end

  describe "authenticated user with APIs" do
    setup :register_and_log_in_user

    setup %{user: user} do
      [org] = Organizations.list_user_organizations(user)

      {:ok, api} =
        Apis.create_api(%{
          name: "My Test API",
          description: "A test API",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, org: org, api: api}
    end

    test "shows stat cards instead of empty state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Total APIs"
    end

    test "shows all nine big-number stat cards", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      for label <- [
            "Total APIs",
            "Total Flows",
            "API Keys",
            "Active APIs",
            "Active Flows",
            "Executions Today",
            "Conversations",
            "Errors Today",
            "LLM Cost (month)"
          ] do
        assert html =~ label, "missing stat card label: #{label}"
      end
    end

    test "does not show empty state when APIs exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      refute html =~ "Welcome to BlackBoex"
    end

    test "shows recent activity section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Recent Activity"
    end

    test "no recent activity shows empty state message", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "No recent activity"
    end
  end

  describe "format helpers via render" do
    setup :register_and_log_in_user

    setup %{user: user} do
      [org] = Organizations.list_user_organizations(user)

      {:ok, api} =
        Apis.create_api(%{
          name: "Helper Test API",
          description: "Tests helper formatting",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      {:ok, org: org, api: api}
    end

    test "zero-cost month renders formatted cost without crashing", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "$0.00"
    end

    test "relative_time renders for recent audit activity", %{conn: conn, org: org} do
      Blackboex.Audit.log("api.created", %{
        organization_id: org.id,
        resource_type: "api",
        resource_id: Ecto.UUID.generate()
      })

      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "ago" or html =~ "just now" or html =~ "Api Created"
    end
  end

  describe "format_action helper" do
    setup :register_and_log_in_user

    setup %{user: user} do
      [org] = Organizations.list_user_organizations(user)

      {:ok, api} =
        Apis.create_api(%{
          name: "Action Format API",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      Blackboex.Audit.log("api.updated", %{
        organization_id: org.id,
        resource_type: "api",
        resource_id: api.id
      })

      {:ok, org: org, api: api}
    end

    test "formats dotted action names by capitalizing each segment", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      # "api.updated" → "Api Updated"
      assert html =~ "Api Updated"
    end
  end

  describe "recent activity with various timestamps" do
    setup :register_and_log_in_user

    setup %{user: user} do
      [org] = Organizations.list_user_organizations(user)

      {:ok, api} =
        Apis.create_api(%{
          name: "Timestamps API",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      for action <- ["api.created", "api.updated", "api.deleted"] do
        Blackboex.Audit.log(action, %{
          organization_id: org.id,
          resource_type: "api",
          resource_id: api.id
        })
      end

      {:ok, org: org, api: api}
    end

    test "shows recent activity items when audit logs exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Api Created" or html =~ "Api Updated" or html =~ "Api Deleted" or
               html =~ "ago" or html =~ "just now"
    end

    test "no recent activity message absent when activity exists", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      refute html =~ "No recent activity"
    end
  end

  describe "relative_time branches via direct audit log timestamps" do
    setup :register_and_log_in_user

    setup %{user: user} do
      [org] = Organizations.list_user_organizations(user)

      {:ok, api} =
        Apis.create_api(%{
          name: "Time Branch API",
          status: "published",
          visibility: "public",
          organization_id: org.id,
          user_id: user.id
        })

      now = DateTime.utc_now()
      now_naive = DateTime.to_naive(now)

      rows =
        for {action, offset_seconds} <- [
              # 2 hours ago → "2h ago"
              {"api.created", -7_200},
              # 2 days ago → "2d ago"
              {"api.updated", -172_800},
              # 8 days ago → calendar format
              {"api.deleted", -691_200}
            ] do
          ts = NaiveDateTime.add(now_naive, offset_seconds, :second)

          %{
            id: Ecto.UUID.dump!(Ecto.UUID.generate()),
            organization_id: Ecto.UUID.dump!(org.id),
            action: action,
            resource_type: "api",
            resource_id: api.id,
            metadata: %{},
            inserted_at: ts
          }
        end

      Blackboex.Repo.insert_all("audit_logs", rows)

      {:ok, org: org, api: api}
    end

    test "renders dashboard with backdated activity without crashing", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"

      assert html =~ "ago" or html =~ "just now" or html =~ "Jan" or html =~ "Feb" or
               html =~ "Mar" or html =~ "Apr" or html =~ "May" or html =~ "Jun" or
               html =~ "Jul" or html =~ "Aug" or html =~ "Sep" or html =~ "Oct" or
               html =~ "Nov" or html =~ "Dec"
    end
  end
end
