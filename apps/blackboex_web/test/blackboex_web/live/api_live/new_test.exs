defmodule BlackboexWeb.ApiLive.NewTest do
  use BlackboexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  @moduletag :liveview

  setup :verify_on_exit!

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/apis/new")
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "renders form with textarea and generate button", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/apis/new")
      assert html =~ "Create API"
      assert has_element?(view, "textarea")
      assert has_element?(view, "button", "Generate")
    end

    test "shows error on empty description", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/apis/new")

      html =
        view
        |> form("#generate-form", %{description: ""})
        |> render_submit()

      assert html =~ "Please enter a description"
    end

    test "shows preview area after generation", %{conn: conn} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content: """
           ```elixir
           def call(conn, %{"celsius" => c}) do
             json(conn, %{fahrenheit: c * 9 / 5 + 32})
           end
           ```
           """,
           usage: %{input_tokens: 50, output_tokens: 100}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/apis/new")

      view
      |> form("#generate-form", %{description: "Convert Celsius to Fahrenheit"})
      |> render_submit()

      # Wait for the async Task to complete
      wait_for_generation(view)

      html = render(view)
      assert html =~ "fahrenheit"
      assert html =~ "Save"
    end

    test "shows name/slug fields after generation", %{conn: conn} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content: "```elixir\ndef call(conn, params), do: json(conn, %{ok: true})\n```",
           usage: %{input_tokens: 10, output_tokens: 20}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/apis/new")

      view
      |> form("#generate-form", %{description: "Test API"})
      |> render_submit()

      wait_for_generation(view)

      html = render(view)
      assert html =~ "Name"
      assert html =~ "Slug"
    end

    test "shows error when generation fails", %{conn: conn} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :api_error}
      end)

      {:ok, view, _html} = live(conn, ~p"/apis/new")

      view
      |> form("#generate-form", %{description: "Some API"})
      |> render_submit()

      wait_for_generation(view)

      html = render(view)
      assert html =~ "Generation failed"
    end

    test "saves generated API as draft", %{conn: conn} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content: "```elixir\ndef call(conn, p), do: json(conn, p)\n```",
           usage: %{input_tokens: 10, output_tokens: 20}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/apis/new")

      view
      |> form("#generate-form", %{description: "A test API"})
      |> render_submit()

      wait_for_generation(view)

      view
      |> form("#save-form", %{name: "My Saved API", slug: "my-saved-api"})
      |> render_submit()

      flash = assert_redirect(view, ~p"/apis")
      assert flash["info"] =~ "saved"
    end

    test "shows validation error on save with empty name", %{conn: conn} do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content: "```elixir\ndef call(conn, p), do: json(conn, p)\n```",
           usage: %{input_tokens: 10, output_tokens: 20}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/apis/new")

      view
      |> form("#generate-form", %{description: "A test API"})
      |> render_submit()

      wait_for_generation(view)

      html =
        view
        |> form("#save-form", %{name: "", slug: ""})
        |> render_submit()

      assert html =~ "name"
      assert html =~ "can&#39;t be blank"
    end
  end

  defp wait_for_generation(view) do
    # Allow the async Task to complete and send result back to LiveView
    Process.sleep(150)
    render(view)
  end
end
