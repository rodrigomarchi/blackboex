defmodule BlackboexWeb.ProjectLive.LlmIntegrationsTest do
  use BlackboexWeb.ConnCase, async: false

  import Mox

  @moduletag :liveview

  alias Blackboex.ProjectEnvVars

  setup [:register_and_log_in_user, :create_org]
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{org: org, user: user} do
    {:ok, %{project: project}} =
      Blackboex.Projects.create_project(org, user, %{name: "LLM Test Project"})

    %{project: project}
  end

  describe "mount (no key configured)" do
    test "shows 'Not configured' with input form", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      assert html =~ "Not configured"
      assert html =~ "Anthropic"
    end

    test "renders tab with 'LLM Integrations' active", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      assert_has(view, ~s([data-tab="llm_integrations"][aria-current="page"]))
    end
  end

  describe "save_key" do
    test "persists key through ProjectEnvVars.put_llm_key", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      render_hook(view, "save_key", %{"llm" => %{"value" => "sk-ant-test-abc123"}})

      assert {:ok, "sk-ant-test-abc123"} = ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "after save, plaintext value does not appear in HTML (masked)", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      html =
        render_hook(view, "save_key", %{
          "llm" => %{"value" => "sk-ant-never-show-me-in-clear"}
        })

      refute html =~ "sk-ant-never-show-me-in-clear"
      # Masked form shown
      assert html =~ "sk-ant"
      assert html =~ "..."
    end

    test "empty value is rejected", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      render_hook(view, "save_key", %{"llm" => %{"value" => "   "}})

      assert {:error, :not_configured} = ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end
  end

  describe "update (key already exists)" do
    setup %{org: org, project: project} do
      llm_anthropic_key_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        value: "sk-ant-old-key-12345"
      })

      :ok
    end

    test "shows masked existing key", %{conn: conn, org: org, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      assert html =~ "Configured"
      # Masked (first 6 + ... + last 4)
      assert html =~ "sk-ant"
      refute html =~ "sk-ant-old-key-12345"
    end

    test "update upserts new value", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      render_hook(view, "save_key", %{"llm" => %{"value" => "sk-ant-new-zzzz-67890"}})

      assert {:ok, "sk-ant-new-zzzz-67890"} =
               ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end

    test "delete_key removes integration", %{conn: conn, org: org, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      render_hook(view, "delete_key", %{})

      assert {:error, :not_configured} =
               ProjectEnvVars.get_llm_key(project.id, :anthropic)
    end
  end

  describe "test_connection" do
    setup %{org: org, project: project} do
      llm_anthropic_key_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        value: "sk-ant-conn-test"
      })

      :ok
    end

    test "shows 'Connection OK' on success", %{conn: conn, org: org, project: project} do
      expect(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:ok, %{content: "pong", usage: %{}}}
      end)

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      html = render_hook(view, "test_connection", %{})

      assert html =~ "Connection OK"
    end

    test "shows 'Invalid key' on 401", %{conn: conn, org: org, project: project} do
      expect(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, :invalid_api_key}
      end)

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      html = render_hook(view, "test_connection", %{})

      assert html =~ "Invalid key"
    end

    test "shows 'Network error' on generic failure", %{conn: conn, org: org, project: project} do
      expect(Blackboex.LLM.ClientMock, :generate_text, fn _prompt, _opts ->
        {:error, :timeout}
      end)

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      html = render_hook(view, "test_connection", %{})

      assert html =~ "Network error"
    end
  end

  describe "plaintext leak prevention" do
    test "plaintext is NEVER stored in socket assigns after save", %{
      conn: conn,
      org: org,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      plaintext = "sk-ant-leaky-plaintext-abcdef-xyz"
      render_hook(view, "save_key", %{"llm" => %{"value" => plaintext}})

      # Read the LiveView process socket assigns directly
      state = :sys.get_state(view.pid)
      assigns_inspect = inspect(state)

      refute assigns_inspect =~ plaintext,
             "plaintext key leaked into LiveView socket state"
    end

    test "plaintext is NEVER stored in assigns at mount when key pre-exists", %{
      conn: conn,
      org: org,
      project: project
    } do
      plaintext = "sk-ant-pre-existing-leaky-xyz-12345"

      llm_anthropic_key_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        value: plaintext
      })

      {:ok, view, _html} =
        live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")

      state = :sys.get_state(view.pid)
      assigns_inspect = inspect(state)

      refute assigns_inspect =~ plaintext,
             "plaintext key leaked into LiveView socket state at mount"
    end
  end

  describe "non-member" do
    test "blocked with 403/404", %{org: org, project: project} do
      other_user = user_fixture()
      other_conn = build_conn() |> log_in_user(other_user)

      conn = get(other_conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/integrations")
      assert conn.status in [403, 404]
    end
  end
end
