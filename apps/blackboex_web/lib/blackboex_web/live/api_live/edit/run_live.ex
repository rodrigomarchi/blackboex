defmodule BlackboexWeb.ApiLive.Edit.RunLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  require Logger

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [history_status_color: 1]

  alias Blackboex.Testing
  alias Blackboex.Testing.RequestExecutor
  alias Blackboex.Testing.ResponseValidator
  alias Blackboex.Testing.SampleData
  alias Blackboex.Testing.SnippetGenerator
  alias BlackboexWeb.ApiLive.Edit.Shared

  @valid_methods ~w(GET POST PUT PATCH DELETE)
  @valid_request_tabs ~w(params headers body auth)
  @valid_response_tabs ~w(body headers)
  @valid_snippet_languages ~w(curl python javascript elixir ruby go)
  @lang_atoms %{
    "curl" => :curl,
    "python" => :python,
    "javascript" => :javascript,
    "elixir" => :elixir,
    "ruby" => :ruby,
    "go" => :go
  }
  @max_test_items 50

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  # ── Mount ─────────────────────────────────────────────────────────────

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} -> {:ok, socket |> init_assigns() |> load_history()}
      {:error, socket} -> {:ok, socket}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="run">
      <div class="flex gap-4 h-full p-4 overflow-hidden">
        <%!-- Request Builder --%>
        <div class="flex-1 min-w-0 overflow-auto">
          <.live_component
            module={BlackboexWeb.Components.Editor.RequestBuilder}
            id="request-builder"
            method={@test_method}
            url={@test_url}
            params={@test_params}
            headers={@test_headers}
            body_json={@test_body_json}
            body_error={@test_body_error}
            api_key={@test_api_key}
            loading={@test_loading}
            active_tab={@request_tab}
          />
        </div>

        <%!-- Response Viewer --%>
        <div class="flex-1 min-w-0 overflow-auto">
          <.live_component
            module={BlackboexWeb.Components.Editor.ResponseViewer}
            id="response-viewer"
            response={@test_response}
            loading={@test_loading}
            error={@test_error}
            violations={@test_violations}
            response_tab={@response_tab}
          />
        </div>

        <%!-- Test History --%>
        <div class="w-52 shrink-0 border-l pl-3 overflow-y-auto">
          <div class="flex items-center justify-between mb-2">
            <h4 class="text-xs font-semibold text-muted-foreground uppercase">History</h4>
            <button
              :if={@test_history != []}
              phx-click="clear_history"
              data-confirm="Clear request history?"
              class="text-[10px] text-destructive hover:underline"
            >
              Clear
            </button>
          </div>

          <div class="flex flex-wrap gap-1 mb-2">
            <button
              :for={lang <- ~w(curl python javascript elixir ruby go)}
              phx-click="copy_snippet"
              phx-value-language={lang}
              class="rounded border px-1.5 py-0.5 text-[10px] hover:bg-accent"
            >
              {lang}
            </button>
          </div>

          <%= if @test_history == [] do %>
            <p class="text-[10px] text-muted-foreground">No requests yet</p>
          <% else %>
            <div class="space-y-1">
              <div
                :for={item <- @test_history}
                phx-click="load_history_item"
                phx-value-id={item.id}
                class="rounded border p-1.5 text-[10px] cursor-pointer hover:bg-accent"
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-1">
                    <span class="font-semibold">{item.method}</span>
                    <span class="text-muted-foreground truncate max-w-[80px]">{item.path}</span>
                  </div>
                  <span class={[
                    "inline-flex rounded-full px-1 py-0 text-[9px] font-semibold",
                    history_status_color(item.response_status)
                  ]}>
                    {item.response_status}
                  </span>
                </div>
                <div class="text-muted-foreground mt-0.5">{item.duration_ms}ms</div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </.editor_shell>
    """
  end

  # ── handle_event: command palette ────────────────────────────────────

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── handle_event: run tab ─────────────────────────────────────────────

  @impl true
  def handle_event("update_test_method", %{"method" => method}, socket)
      when method in @valid_methods do
    {:noreply, assign(socket, test_method: method)}
  end

  def handle_event("update_test_method", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_test_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, test_url: url)}
  end

  @impl true
  def handle_event("switch_request_tab", %{"tab" => tab}, socket)
      when tab in @valid_request_tabs do
    {:noreply, assign(socket, request_tab: tab)}
  end

  def handle_event("switch_request_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_response_tab", %{"tab" => tab}, socket)
      when tab in @valid_response_tabs do
    {:noreply, assign(socket, response_tab: tab)}
  end

  def handle_event("switch_response_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_test_body", %{"test_body_json" => body}, socket) do
    body_error =
      case Jason.decode(body) do
        {:ok, _} -> nil
        {:error, _} -> "Invalid JSON"
      end

    {:noreply, assign(socket, test_body_json: body, test_body_error: body_error)}
  end

  @impl true
  def handle_event("update_test_api_key", %{"test_api_key" => key}, socket) do
    {:noreply, assign(socket, test_api_key: key)}
  end

  @impl true
  def handle_event("add_param", _params, socket) do
    if length(socket.assigns.test_params) >= @max_test_items do
      {:noreply, put_flash(socket, :error, "Maximum #{@max_test_items} parameters allowed")}
    else
      new_param = %{key: "", value: "", id: Ecto.UUID.generate()}
      {:noreply, assign(socket, test_params: socket.assigns.test_params ++ [new_param])}
    end
  end

  @impl true
  def handle_event("remove_param", %{"id" => id}, socket) do
    params = Enum.reject(socket.assigns.test_params, &(&1.id == id))
    {:noreply, assign(socket, test_params: params)}
  end

  @impl true
  def handle_event("update_param_key", %{"id" => id, "param_key" => key}, socket) do
    params = update_item(socket.assigns.test_params, id, :key, key)
    {:noreply, assign(socket, test_params: params)}
  end

  @impl true
  def handle_event("update_param_value", %{"id" => id, "param_value" => value}, socket) do
    params = update_item(socket.assigns.test_params, id, :value, value)
    {:noreply, assign(socket, test_params: params)}
  end

  @impl true
  def handle_event("add_header", _params, socket) do
    if length(socket.assigns.test_headers) >= @max_test_items do
      {:noreply, put_flash(socket, :error, "Maximum #{@max_test_items} headers allowed")}
    else
      new_header = %{key: "", value: "", id: Ecto.UUID.generate()}
      {:noreply, assign(socket, test_headers: socket.assigns.test_headers ++ [new_header])}
    end
  end

  @impl true
  def handle_event("remove_header", %{"id" => id}, socket) do
    headers = Enum.reject(socket.assigns.test_headers, &(&1.id == id))
    {:noreply, assign(socket, test_headers: headers)}
  end

  @impl true
  def handle_event("update_header_key", %{"id" => id, "header_key" => key}, socket) do
    headers = update_item(socket.assigns.test_headers, id, :key, key)
    {:noreply, assign(socket, test_headers: headers)}
  end

  @impl true
  def handle_event("update_header_value", %{"id" => id, "header_value" => value}, socket) do
    headers = update_item(socket.assigns.test_headers, id, :value, value)
    {:noreply, assign(socket, test_headers: headers)}
  end

  @impl true
  def handle_event("send_request", _params, %{assigns: %{test_loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("send_request", _params, socket) do
    request = build_request(socket.assigns)

    task =
      Task.async(fn ->
        RequestExecutor.execute(request, plug: BlackboexWeb.Endpoint)
      end)

    {:noreply, assign(socket, test_loading: true, test_error: nil, test_ref: task.ref)}
  end

  @impl true
  def handle_event("quick_test", _params, %{assigns: %{test_loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("quick_test", %{"method" => method}, socket)
      when method in @valid_methods do
    body =
      if method == "POST" do
        sample = SampleData.generate(socket.assigns.api)
        Jason.encode!(sample.happy_path)
      else
        socket.assigns.test_body_json
      end

    socket = assign(socket, test_method: method, test_body_json: body)
    request = build_request(socket.assigns)

    task =
      Task.async(fn ->
        RequestExecutor.execute(request, plug: BlackboexWeb.Endpoint)
      end)

    {:noreply, assign(socket, test_loading: true, test_error: nil, test_ref: task.ref)}
  end

  @impl true
  def handle_event("generate_sample", _params, socket) do
    sample = SampleData.generate(socket.assigns.api)
    body = Jason.encode!(sample.happy_path, pretty: true)
    {:noreply, assign(socket, test_body_json: body, test_body_error: nil, request_tab: "body")}
  end

  @impl true
  def handle_event("copy_snippet", %{"language" => lang}, socket)
      when lang in @valid_snippet_languages do
    request = %{
      method: socket.assigns.test_method,
      url: "http://localhost:4000#{socket.assigns.test_url}",
      headers: build_header_list(socket.assigns.test_headers),
      body: socket.assigns.test_body_json,
      api_key: if(socket.assigns.test_api_key != "", do: socket.assigns.test_api_key, else: nil)
    }

    snippet = SnippetGenerator.generate(socket.assigns.api, @lang_atoms[lang], request)

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: snippet})
     |> put_flash(:info, "#{lang} snippet copied!")}
  end

  def handle_event("copy_snippet", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("load_history_item", %{"id" => id}, socket) do
    api_id = socket.assigns.api.id

    case Testing.get_test_request(id) do
      {:ok, %{api_id: ^api_id} = item} ->
        headers =
          Enum.map(item.headers || %{}, fn {k, v} ->
            %{key: k, value: v, id: Ecto.UUID.generate()}
          end)

        response = %{
          status: item.response_status,
          headers: item.response_headers || %{},
          body: item.response_body || "",
          duration_ms: item.duration_ms
        }

        {:noreply,
         assign(socket,
           test_method: item.method,
           test_headers: headers,
           test_body_json: item.body || "{}",
           test_response: response,
           test_violations: validate_response(response, socket.assigns.api),
           response_tab: "body"
         )}

      {:ok, _item} ->
        {:noreply, put_flash(socket, :error, "Request not found")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Request not found")}
    end
  end

  @impl true
  def handle_event("clear_history", _params, socket) do
    Testing.clear_history(socket.assigns.api.id)
    {:noreply, assign(socket, test_history: [])}
  end

  # ── handle_info: test results ─────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, %{assigns: %{test_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, response} ->
        violations = validate_response(response, socket.assigns.api)
        scope = socket.assigns.current_scope

        Testing.create_test_request(%{
          api_id: socket.assigns.api.id,
          user_id: scope.user.id,
          method: socket.assigns.test_method,
          path: socket.assigns.test_url,
          headers: headers_to_persist(socket.assigns),
          body: socket.assigns.test_body_json,
          response_status: response.status,
          response_headers: response.headers,
          response_body: response.body,
          duration_ms: response.duration_ms
        })

        history = Testing.list_test_requests(socket.assigns.api.id)

        {:noreply,
         assign(socket,
           test_response: response,
           test_loading: false,
           test_error: nil,
           test_violations: violations,
           test_history: history,
           response_tab: "body",
           test_ref: nil
         )}

      {:error, :forbidden} ->
        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "URL not allowed. Only /api/{username}/{slug}/* is accepted."
         )}

      {:error, :timeout} ->
        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Timeout: the request took too long."
         )}

      {:error, reason} ->
        Logger.warning("Test request failed: #{inspect(reason)}")

        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Connection error. Check if the API is compiled."
         )}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{test_ref: ref}} = socket) do
    {:noreply, assign(socket, test_loading: false, test_ref: nil)}
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp init_assigns(socket) do
    api = socket.assigns.api
    org = socket.assigns.org

    assign(socket,
      test_method: api.method || "GET",
      test_url: "/api/#{org.slug}/#{api.slug}",
      test_params: [],
      test_headers: [
        %{key: "Content-Type", value: "application/json", id: Ecto.UUID.generate()}
      ],
      test_body_json: default_test_body(api),
      test_body_error: nil,
      test_api_key: "",
      test_response: nil,
      test_loading: false,
      test_error: nil,
      test_violations: [],
      test_history: [],
      history_loaded: false,
      request_tab: "body",
      response_tab: "body",
      test_ref: nil
    )
  end

  defp load_history(socket) do
    history = Testing.list_test_requests(socket.assigns.api.id)
    assign(socket, test_history: history, history_loaded: true)
  end

  defp default_test_body(api) do
    if api.example_request do
      Jason.encode!(api.example_request, pretty: true)
    else
      "{}"
    end
  end

  defp build_request(assigns) do
    headers = build_header_list(assigns.test_headers)

    headers =
      if assigns.test_api_key != "" do
        headers ++ [{"x-api-key", assigns.test_api_key}]
      else
        headers
      end

    method = assigns.test_method |> String.downcase() |> String.to_existing_atom()

    body =
      if method in [:post, :put, :patch],
        do: assigns.test_body_json,
        else: nil

    %{method: method, url: assigns.test_url, headers: headers, body: body}
  end

  defp build_header_list(headers) do
    headers
    |> Enum.filter(fn h -> h.key != "" end)
    |> Enum.map(fn h -> {h.key, h.value} end)
  end

  defp headers_to_persist(assigns) do
    assigns.test_headers
    |> Enum.filter(fn h -> h.key != "" end)
    |> Map.new(fn h -> {h.key, h.value} end)
  end

  defp validate_response(response, api) do
    ResponseValidator.validate(response, api.param_schema)
  end

  defp update_item(items, id, field, value) do
    Enum.map(items, fn item ->
      if item.id == id, do: Map.put(item, field, value), else: item
    end)
  end

  defp shared_shell_assigns(assigns) do
    Map.take(assigns, [
      :api,
      :versions,
      :selected_version,
      :generation_status,
      :validation_report,
      :test_summary,
      :command_palette_open,
      :command_palette_query,
      :command_palette_selected
    ])
  end
end
