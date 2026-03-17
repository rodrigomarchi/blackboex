defmodule BlackboexWeb.ApiLive.Show do
  @moduledoc """
  LiveView for viewing an API's details, compiling, and testing it.
  """

  use BlackboexWeb, :live_view

  alias Blackboex.Apis
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    org = resolve_organization(socket, params)

    case org && Apis.get_api(org.id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "API not found")
         |> push_navigate(to: ~p"/apis")}

      api ->
        {:ok,
         assign(socket,
           api: api,
           org: org,
           page_title: api.name,
           compile_errors: nil,
           test_result: nil,
           test_body: ~s|{"n": 5}|,
           compiling: false
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">{@api.name}</h1>
            <p class="text-muted-foreground">{@api.description}</p>
          </div>
          <div class="flex items-center gap-3">
            <span class={[
              "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
              status_color(@api.status)
            ]}>
              {@api.status}
            </span>
            <.link
              navigate={~p"/apis"}
              class="text-sm text-muted-foreground hover:text-foreground"
            >
              Back to APIs
            </.link>
          </div>
        </div>

        <%= if @api.source_code do %>
          <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold">Source Code</h2>
              <div class="flex items-center gap-2">
                <button
                  phx-click="compile"
                  disabled={@compiling}
                  class="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90 disabled:opacity-50"
                >
                  <%= if @compiling do %>
                    Compiling...
                  <% else %>
                    Compile
                  <% end %>
                </button>
              </div>
            </div>
            <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm"><code>{@api.source_code}</code></pre>
          </div>
        <% end %>

        <%= if @compile_errors do %>
          <div class="rounded-lg border border-destructive bg-destructive/10 p-4 text-sm text-destructive space-y-1">
            <p class="font-semibold">Compilation failed:</p>
            <ul class="list-disc list-inside">
              <%= for error <- @compile_errors do %>
                <li>{error}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <%= if @api.status in ["compiled", "published"] do %>
          <div class="rounded-lg border bg-card p-6 text-card-foreground shadow-sm space-y-4">
            <h2 class="text-lg font-semibold">API Endpoint</h2>
            <div class="flex items-center gap-2">
              <code class="rounded bg-muted px-2 py-1 text-sm">
                POST /api/{@org.slug}/{@api.slug}
              </code>
            </div>

            <form phx-submit="test_api" phx-change="update_test_body" class="space-y-4">
              <h3 class="text-sm font-medium">Test your API</h3>
              <div class="space-y-2">
                <label for="test-body" class="text-sm text-muted-foreground">
                  Request body (JSON)
                </label>
                <textarea
                  id="test-body"
                  name="test_body"
                  rows="3"
                  class="w-full rounded-md border bg-background px-3 py-2 text-sm font-mono"
                  placeholder={~s({"n": 5})}
                >{@test_body}</textarea>
              </div>
              <div class="flex items-center gap-2">
                <button
                  type="submit"
                  class="inline-flex items-center justify-center rounded-md border px-3 py-1.5 text-sm font-medium hover:bg-accent"
                >
                  Send POST
                </button>
                <button
                  type="button"
                  phx-click="test_api_get"
                  class="inline-flex items-center justify-center rounded-md border px-3 py-1.5 text-sm font-medium hover:bg-accent"
                >
                  Send GET
                </button>
              </div>
            </form>

            <%= if @test_result do %>
              <div>
                <p class="text-xs text-muted-foreground mb-1">Response:</p>
                <pre class="overflow-x-auto rounded-md bg-muted p-4 text-sm"><code>{@test_result}</code></pre>
              </div>
            <% end %>

            <div class="text-xs text-muted-foreground">
              <p class="font-medium mb-1">Or test via curl:</p>
              <pre class="overflow-x-auto rounded-md bg-muted p-2 text-xs"><code>curl -X POST http://localhost:4000/api/{@org.slug}/{@api.slug} -H "Content-Type: application/json" -d '{@test_body}'</code></pre>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("compile", _params, socket) do
    api = socket.assigns.api
    org = socket.assigns.org

    case Compiler.compile(api, api.source_code) do
      {:ok, module} ->
        {:ok, updated_api} = Apis.update_api(api, %{status: "compiled"})

        Registry.register(api.id, module,
          username: org.slug,
          slug: api.slug
        )

        {:noreply,
         assign(socket,
           api: updated_api,
           compile_errors: nil,
           compiling: false
         )}

      {:error, {:validation, reasons}} ->
        {:noreply, assign(socket, compile_errors: reasons, compiling: false)}

      {:error, {:compilation, reason}} ->
        {:noreply, assign(socket, compile_errors: [reason], compiling: false)}
    end
  end

  @impl true
  def handle_event("test_api", %{"test_body" => body}, socket) do
    run_test(socket, :post, body)
  end

  @impl true
  def handle_event("test_api", _params, socket) do
    run_test(socket, :post, socket.assigns.test_body)
  end

  @impl true
  def handle_event("test_api_get", _params, socket) do
    run_test(socket, :get, nil)
  end

  @impl true
  def handle_event("update_test_body", %{"test_body" => body}, socket) do
    {:noreply, assign(socket, test_body: body)}
  end

  defp run_test(socket, method, body) do
    api = socket.assigns.api

    case ensure_registered(api, socket.assigns.org) do
      {:ok, module} ->
        conn = build_test_conn(method, body)

        try do
          result_conn = module.call(conn, module.init([]))
          formatted = format_response(result_conn)

          {:noreply,
           assign(socket, test_result: formatted, test_body: body || socket.assigns.test_body)}
        rescue
          error ->
            {:noreply, assign(socket, test_result: "Error: #{Exception.message(error)}")}
        end

      {:error, reason} ->
        {:noreply, assign(socket, test_result: "Failed to load API: #{inspect(reason)}")}
    end
  end

  defp ensure_registered(api, org) do
    case Registry.lookup(api.id) do
      {:ok, module} ->
        {:ok, module}

      {:error, :not_found} ->
        # Module lost (server restart / hot reload) — recompile from source
        with {:ok, module} <- Compiler.compile(api, api.source_code) do
          Registry.register(api.id, module, username: org.slug, slug: api.slug)
          {:ok, module}
        end
    end
  end

  defp build_test_conn(:get, _body) do
    Plug.Test.conn(:get, "/")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  defp build_test_conn(:post, body) when is_binary(body) and body != "" do
    Plug.Test.conn(:post, "/", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  defp build_test_conn(:post, _body) do
    Plug.Test.conn(:post, "/", "{}")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  defp format_response(conn) do
    status = conn.status

    body =
      case Jason.decode(conn.resp_body) do
        {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
        {:error, _} -> conn.resp_body
      end

    "HTTP #{status}\n#{body}"
  end

  defp resolve_organization(socket, params) do
    scope = socket.assigns.current_scope

    case params["org"] do
      nil ->
        scope.organization

      org_id ->
        org = Blackboex.Organizations.get_organization(org_id)

        if org && Blackboex.Organizations.get_user_membership(org, scope.user) do
          org
        else
          nil
        end
    end
  end

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"
end
