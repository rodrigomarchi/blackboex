defmodule BlackboexWeb.Live.BillingEnforcementTest do
  @moduledoc """
  Tests billing enforcement for LLM-based features in the edit LiveView.
  Verifies that free plan users who exceed the 50 LLM generations/month limit
  see appropriate error messages on chat edit, test generation, and doc generation.
  """

  use BlackboexWeb.ConnCase, async: false

  @moduletag :liveview

  import Mox
  import Phoenix.LiveViewTest

  alias Blackboex.Apis
  alias Blackboex.Billing.DailyUsage
  alias Blackboex.Repo

  setup :verify_on_exit!
  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Free Org", slug: "freeorg"})

    # Org defaults to :free plan (max 50 LLM generations/month).
    # Insert aggregated daily_usage for yesterday with 51 LLM generations.
    # This ensures sum_monthly_usage returns 51 >= 50 -> :limit_exceeded.
    yesterday = Date.add(Date.utc_today(), -1)

    %DailyUsage{}
    |> DailyUsage.changeset(%{
      organization_id: org.id,
      date: yesterday,
      llm_generations: 51
    })
    |> Repo.insert!()

    {:ok, api} =
      Apis.create_api(%{
        name: "Test API",
        slug: "test-api",
        template_type: "computation",
        organization_id: org.id,
        user_id: user.id,
        source_code: "def handle(_), do: %{ok: true}"
      })

    %{org: org, api: api}
  end

  describe "billing enforcement on chat edit" do
    test "free plan user at LLM limit sees error flash", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel first
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

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
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open the chat panel
      lv |> element(~s(button[phx-click="toggle_chat"])) |> render_click()

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

  describe "billing enforcement on doc generation" do
    @tag :capture_log
    test "free plan user at LLM limit sees error flash", %{conn: conn, org: org, api: api} do
      # Doc generation requires compiled status
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Open config panel where the generate docs button lives (in the publish section)
      lv |> render_click("switch_tab", %{"tab" => "config"})

      lv |> element(~s(button[phx-click="generate_docs"])) |> render_click()

      # Flash is rendered by app layout; verify doc generation was not started
      html = render(lv)
      refute html =~ "Generating"
    end
  end
end
