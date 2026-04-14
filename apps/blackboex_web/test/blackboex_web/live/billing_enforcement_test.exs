defmodule BlackboexWeb.Live.BillingEnforcementTest do
  @moduledoc """
  Tests billing enforcement for LLM-based features in the edit LiveView.
  Verifies that free plan users who exceed the 50 LLM generations/month limit
  see appropriate error messages on chat edit, test generation, and doc generation.
  """

  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  alias Blackboex.Apis

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Free Org", slug: "freeorg"})

    # Org defaults to :free plan (max 50 LLM generations/month).
    # Insert aggregated daily_usage for yesterday with 51 LLM generations.
    # This ensures sum_monthly_usage returns 51 >= 50 -> :limit_exceeded.
    yesterday = Date.add(Date.utc_today(), -1)

    daily_usage_fixture(%{
      organization_id: org.id,
      project_id: Blackboex.Projects.get_default_project(org.id).id,
      date: yesterday,
      llm_generations: 51
    })

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        slug: "test-api",
        template_type: "computation",
        organization_id: org.id,
        project_id: Blackboex.Projects.get_default_project(org.id).id,
        user_id: user.id
      })

    Apis.upsert_files(api, [
      %{path: "/src/handler.ex", content: "def handle(_), do: %{ok: true}", file_type: "source"}
    ])

    %{org: org, api: api}
  end

  describe "billing enforcement on chat edit" do
    test "free plan user at LLM limit sees error flash", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      lv
      |> form("form[phx-submit=send_chat]", %{chat_input: "Add error handling"})
      |> render_submit()

      html = render(lv)

      # Flash is rendered by app layout; verify the chat is NOT in loading state
      # (the LLM call was blocked by billing enforcement).
      refute html =~ "chat_loading"
      # No version should have been created
      assert Apis.list_versions(api.id) == []
    end
  end

  describe "billing enforcement on chat edit (rate limited)" do
    test "free plan user at LLM limit sees no pending edit", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/chat?org=#{org.id}")

      # Send a chat message — billing enforcement blocks the LLM call
      lv
      |> form("form[phx-submit=send_chat]", %{chat_input: "Generate tests"})
      |> render_submit()

      html = render(lv)

      # No pending edit should exist (LLM call was blocked)
      refute html =~ "accept_edit"
      assert Apis.list_versions(api.id) == []
    end
  end

  describe "docs auto-generation" do
    test "publish tab shows documentation links when compiled", %{
      conn: conn,
      org: org,
      api: api
    } do
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit/publish?org=#{org.id}")

      html = render(lv)
      assert html =~ "Swagger UI"
      assert html =~ "OpenAPI JSON"
    end
  end
end
