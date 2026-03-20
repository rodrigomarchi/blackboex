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

      lv
      |> form("form[phx-submit=send_chat]", %{chat_input: "Add error handling"})
      |> render_submit()

      html = render(lv)

      assert html =~ "LLM generation limit reached"
    end
  end

  describe "billing enforcement on test generation" do
    test "free plan user at LLM limit sees error flash", %{conn: conn, org: org, api: api} do
      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Switch to auto_tests tab where the generate button lives
      lv
      |> element(~s(button[phx-click="switch_tab"][phx-value-tab="auto_tests"]))
      |> render_click()

      html = lv |> element(~s(button[phx-click="generate_tests"])) |> render_click()

      assert html =~ "LLM generation limit reached"
    end
  end

  describe "billing enforcement on doc generation" do
    @tag :capture_log
    test "free plan user at LLM limit sees error flash", %{conn: conn, org: org, api: api} do
      # Doc generation requires compiled status
      {:ok, _api} = Apis.update_api(api, %{status: "compiled"})

      {:ok, lv, _html} = live(conn, ~p"/apis/#{api.id}/edit?org=#{org.id}")

      # Switch to publish tab where the generate docs button lives
      lv |> element(~s(button[phx-click="switch_tab"][phx-value-tab="publish"])) |> render_click()

      html = lv |> element(~s(button[phx-click="generate_docs"])) |> render_click()

      assert html =~ "LLM generation limit reached"
    end
  end
end
