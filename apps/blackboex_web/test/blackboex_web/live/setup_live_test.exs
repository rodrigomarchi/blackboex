defmodule BlackboexWeb.SetupLiveTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Blackboex.Accounts
  alias Blackboex.Organizations
  alias Blackboex.Repo
  alias Blackboex.Settings

  @valid_attrs %{
    "app_name" => "My Blackboex",
    "public_url" => "http://localhost:4000",
    "email" => "admin@example.com",
    "password" => "supersecretpw1234",
    "password_confirmation" => "supersecretpw1234",
    "org_name" => "Acme"
  }

  setup do
    Settings.invalidate_cache()
    on_exit(fn -> Settings.invalidate_cache() end)
    :ok
  end

  describe "mount when setup not completed" do
    test "renders wizard with auth layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/setup")
      # auth layout has logo block, not the app sidebar
      assert html =~ "First-run setup"
      refute html =~ "id=\"app-sidebar"
    end

    test "renders <.header>, <.card> and form fields via design-system components", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/setup")
      # Header component fingerprint
      assert html =~ "text-lg font-semibold leading-8"
      # Card component fingerprint
      assert html =~ "rounded-xl border bg-card"
      # Input via FormField component fingerprint
      assert html =~ "rounded-md border border-input bg-background"
      # Button component fingerprint
      assert html =~ "inline-flex items-center justify-center gap-2"
    end

    test "starts on the instance step", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/setup")
      assert html =~ "App name"
      assert html =~ "Public URL"
      refute html =~ "Admin email"
    end
  end

  describe "mount when setup is completed" do
    setup do
      instance_setting_fixture()
      :ok
    end

    test "returns 404 (RequireSetup plug halts)", %{conn: conn} do
      conn = get(conn, ~p"/setup")
      assert conn.status == 404
    end
  end

  describe "step navigation" do
    test "step 1 (instance) requires app_name and public_url to advance", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")

      html =
        view
        |> form("#setup-instance", setup: %{"app_name" => "", "public_url" => ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      # Did not advance
      assert html =~ "App name"
      refute html =~ "Admin email"
    end

    test "advances to admin step when instance fields are valid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")

      html =
        view
        |> form("#setup-instance",
          setup: %{
            "app_name" => @valid_attrs["app_name"],
            "public_url" => @valid_attrs["public_url"]
          }
        )
        |> render_submit()

      assert html =~ "Admin email"
    end

    test "step 2 (admin) requires email and matching password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      advance_to_admin(view)

      html =
        view
        |> form("#setup-admin",
          setup: %{
            "email" => "not-an-email",
            "password" => "short",
            "password_confirmation" => "different"
          }
        )
        |> render_submit()

      # Stays on admin
      assert html =~ "Admin email"
      assert html =~ "Password"
    end

    test "step 3 requires org_name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      advance_to_admin(view)
      advance_to_org(view)

      html =
        view
        |> form("#setup-org", setup: %{"org_name" => ""})
        |> render_submit()

      assert html =~ "Organization name"
    end

    test "back returns to previous step preserving values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      advance_to_admin(view)

      html = view |> element("button[phx-click=back]") |> render_click()

      assert html =~ "App name"
      # Value preserved
      assert html =~ @valid_attrs["app_name"]
    end

    test "review step shows entered values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      advance_to_admin(view)
      advance_to_org(view)
      html = advance_to_review(view)

      assert html =~ "Review"
      assert html =~ @valid_attrs["app_name"]
      assert html =~ @valid_attrs["email"]
      assert html =~ @valid_attrs["org_name"]
    end
  end

  describe "submit" do
    test "completes setup and redirects to /setup/finish?token=...", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      advance_to_admin(view)
      advance_to_org(view)
      _ = advance_to_review(view)

      assert {:error, {:redirect, %{to: to}}} =
               view |> element("button[phx-click=complete]") |> render_click()

      assert to =~ ~r{^/setup/finish\?token=}

      # Side-effects
      assert Accounts.get_user_by_email(@valid_attrs["email"])
      assert Repo.aggregate(Organizations.Organization, :count, :id) >= 1
      assert Settings.setup_completed?()
    end

    test "after submit, /setup returns 404", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      advance_to_admin(view)
      advance_to_org(view)
      _ = advance_to_review(view)

      _ = view |> element("button[phx-click=complete]") |> render_click()

      conn = get(build_conn(), ~p"/setup")
      assert conn.status == 404
    end
  end

  describe "visual contract" do
    test "html contains design-system fingerprints (no raw <h1>)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/setup")

      # Header component fingerprint (forbids raw <h1 class="setup-...">)
      assert html =~ "text-lg font-semibold leading-8"
      refute html =~ "class=\"setup-"
    end

    test "every <button> rendered by the wizard form has the design-system button fingerprint",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/setup")
      html = view |> element("#setup-instance") |> render()

      buttons = Regex.scan(~r/<button[^>]*>/, html)
      assert buttons != []

      Enum.each(buttons, fn [tag] ->
        assert tag =~ "inline-flex items-center justify-center gap-2",
               "raw <button> without design-system class fingerprint: #{tag}"
      end)
    end

    test "no setup-only ad-hoc CSS classes are introduced", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/setup")

      refute html =~ "setup-wizard"
      refute html =~ "setup-step"
      refute html =~ "setup-form"
    end
  end

  defp advance_to_admin(view) do
    view
    |> form("#setup-instance",
      setup: %{
        "app_name" => @valid_attrs["app_name"],
        "public_url" => @valid_attrs["public_url"]
      }
    )
    |> render_submit()
  end

  defp advance_to_org(view) do
    view
    |> form("#setup-admin",
      setup: %{
        "email" => @valid_attrs["email"],
        "password" => @valid_attrs["password"],
        "password_confirmation" => @valid_attrs["password_confirmation"]
      }
    )
    |> render_submit()
  end

  defp advance_to_review(view) do
    view
    |> form("#setup-org",
      setup: %{
        "org_name" => @valid_attrs["org_name"]
      }
    )
    |> render_submit()
  end
end
