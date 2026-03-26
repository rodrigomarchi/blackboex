defmodule BlackboexWeb.Components.QuickActionsTest do
  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Phoenix.LiveViewTest

  alias Blackboex.Apis

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org", slug: "testorg"})

    %{org: org, user: user}
  end

  defp open_chat(lv) do
    lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()
  end

  describe "quick actions" do
    test "renders general quick action buttons for computation template", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, api} =
        Apis.create_api(%{
          name: "Quick Action API",
          slug: "quick-action",
          template_type: "computation",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle(params), do: params"
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = render(lv)
      assert html =~ "quick_action"
    end

    test "renders CRUD-specific quick actions for crud template", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, api} =
        Apis.create_api(%{
          name: "CRUD API",
          slug: "crud-api",
          template_type: "crud",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle_list(params), do: []"
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = render(lv)
      # CRUD-specific actions
      assert html =~ "filter" || html =~ "pagination" || html =~ "Filter" || html =~ "Pagination"
    end

    test "renders webhook-specific quick actions for webhook template", %{
      conn: conn,
      org: org,
      user: user
    } do
      {:ok, api} =
        Apis.create_api(%{
          name: "Webhook API",
          slug: "webhook-api",
          template_type: "webhook",
          organization_id: org.id,
          user_id: user.id,
          source_code: "def handle_webhook(payload), do: :ok"
        })

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")
      open_chat(lv)

      html = render(lv)
      # Webhook-specific actions
      assert html =~ "signature" || html =~ "Signature"
    end
  end
end
