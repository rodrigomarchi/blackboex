defmodule BlackboexWeb.ApiLive.Edit do
  @moduledoc """
  LiveView for editing API code with Monaco Editor, versioning, and compilation.
  """

  use BlackboexWeb, :live_view

  require Logger

  alias Blackboex.Apis
  alias Blackboex.Apis.Conversations
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.Apis.Registry
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.LLM.Config
  alias Blackboex.LLM.EditPrompts
  alias Blackboex.Testing
  alias Blackboex.Testing.RequestExecutor
  alias Blackboex.Testing.ResponseValidator
  alias Blackboex.Testing.SampleData
  alias Blackboex.Testing.SnippetGenerator

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
        # Authorization: resolve_organization already verified membership.
        # org is nil if user has no membership → api lookup returns nil → redirected above.
        versions = Apis.list_versions(api.id)
        {:ok, conversation} = Conversations.get_or_create_conversation(api.id)

        {:ok,
         assign(socket,
           api: api,
           org: org,
           code: api.source_code || "",
           page_title: "Edit: #{api.name}",
           compile_errors: nil,
           compile_success: false,
           saving: false,
           tab: "info",
           versions: versions,
           selected_version: nil,
           diff_old: nil,
           diff_new: nil,
           chat_messages: conversation.messages,
           chat_input: "",
           chat_loading: false,
           chat_conversation: conversation,
           pending_edit: nil,
           # Test tab assigns
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
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">{@api.name}</h1>
            <p class="text-sm text-muted-foreground">{@api.description}</p>
          </div>
          <div class="flex items-center gap-2">
            <span class={[
              "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
              status_color(@api.status)
            ]}>
              {@api.status}
            </span>
            <.link
              navigate={~p"/apis/#{@api.id}"}
              class="text-sm text-muted-foreground hover:text-foreground"
            >
              Back
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-12 gap-4">
          <%!-- Chat Panel (25%) --%>
          <div class="col-span-3 rounded-lg border bg-card text-card-foreground shadow-sm max-h-[700px]">
            <.live_component
              module={BlackboexWeb.Components.ChatPanel}
              id="chat-panel"
              messages={@chat_messages}
              input={@chat_input}
              loading={@chat_loading}
              api_id={@api.id}
              pending_edit={@pending_edit}
              template_type={@api.template_type}
            />
          </div>

          <%!-- Editor Panel (50%) — hidden when Test tab active --%>
          <div class={[
            "col-span-6 rounded-lg border bg-card text-card-foreground shadow-sm",
            if(@tab == "test", do: "hidden")
          ]}>
            <div class="flex items-center justify-between border-b px-4 py-2">
              <h2 class="text-sm font-semibold">Code Editor</h2>
              <div class="flex items-center gap-2">
                <button
                  phx-click="save"
                  disabled={@saving}
                  class="inline-flex items-center rounded-md border px-3 py-1 text-xs font-medium hover:bg-accent"
                >
                  Save
                </button>
                <button
                  phx-click="save_and_compile"
                  class="inline-flex items-center rounded-md bg-primary px-3 py-1 text-xs font-medium text-primary-foreground hover:bg-primary/90"
                >
                  Save & Compile
                </button>
              </div>
            </div>
            <div style="min-height: 500px;">
              <LiveMonacoEditor.code_editor
                path={"api_#{@api.id}.ex"}
                value={@code}
                change="code_changed"
                style="min-height: 500px; width: 100%;"
                opts={
                  Map.merge(LiveMonacoEditor.default_opts(), %{
                    "language" => "elixir",
                    "fontSize" => 14,
                    "minimap" => %{"enabled" => false},
                    "wordWrap" => "on",
                    "scrollBeyondLastLine" => false,
                    "readOnly" => @selected_version != nil
                  })
                }
              />
            </div>
          </div>

          <%!-- Test Panel (50%) — shown when Test tab active --%>
          <%= if @tab == "test" do %>
            <div class="col-span-6 space-y-4">
              <.live_component
                module={BlackboexWeb.Components.RequestBuilder}
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

              <.live_component
                module={BlackboexWeb.Components.ResponseViewer}
                id="response-viewer"
                response={@test_response}
                loading={@test_loading}
                error={@test_error}
                violations={@test_violations}
                response_tab={@response_tab}
              />
            </div>
          <% end %>

          <%!-- Side Panel (25%) --%>
          <div class="col-span-3 space-y-4">
            <%!-- Tabs --%>
            <div class="rounded-lg border bg-card text-card-foreground shadow-sm">
              <div class="flex border-b">
                <button
                  :for={t <- ["info", "versions", "test"]}
                  phx-click="switch_tab"
                  phx-value-tab={t}
                  class={[
                    "flex-1 px-3 py-2 text-xs font-medium border-b-2",
                    if(t == @tab,
                      do: "border-primary text-primary",
                      else: "border-transparent text-muted-foreground hover:text-foreground"
                    )
                  ]}
                >
                  {tab_label(t)}
                </button>
              </div>

              <div class="p-4">
                {render_tab(assigns)}
              </div>
            </div>

            <%!-- Compile Errors --%>
            <%= if @compile_errors do %>
              <div class="rounded-lg border border-destructive bg-destructive/10 p-3 text-xs text-destructive space-y-1">
                <p class="font-semibold">Compilation failed:</p>
                <ul class="list-disc list-inside">
                  <%= for error <- @compile_errors do %>
                    <li>{error}</li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%= if @compile_success do %>
              <div class="rounded-lg border border-green-500 bg-green-50 p-3 text-xs text-green-700">
                Compiled successfully. API available at
                <code class="font-mono">/api/{@org.slug}/{@api.slug}</code>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp render_tab(%{tab: "info"} = assigns) do
    ~H"""
    <div class="space-y-3 text-sm">
      <div>
        <span class="text-muted-foreground">Name:</span>
        <span class="font-medium ml-1">{@api.name}</span>
      </div>
      <div>
        <span class="text-muted-foreground">Slug:</span>
        <code class="ml-1">{@api.slug}</code>
      </div>
      <div>
        <span class="text-muted-foreground">Template:</span>
        <span class="ml-1">{@api.template_type}</span>
      </div>
      <div>
        <span class="text-muted-foreground">Status:</span>
        <span class="ml-1">{@api.status}</span>
      </div>
      <%= if @api.status in ["compiled", "published"] do %>
        <div>
          <span class="text-muted-foreground">URL:</span>
          <code class="ml-1">/api/{@org.slug}/{@api.slug}</code>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "versions"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @selected_version do %>
        <button
          phx-click="clear_version_view"
          class="text-xs text-primary hover:underline mb-2"
        >
          Back to current code
        </button>
      <% end %>

      <%= if @versions == [] do %>
        <p class="text-sm text-muted-foreground">
          No versions yet. Save to create the first version.
        </p>
      <% else %>
        <%= for version <- @versions do %>
          <div class={[
            "rounded border p-2 text-xs space-y-1",
            if(@selected_version && @selected_version.id == version.id,
              do: "border-primary bg-primary/5",
              else: ""
            )
          ]}>
            <div class="flex items-center justify-between">
              <span class="font-semibold">v{version.version_number}</span>
              <span class="text-muted-foreground">
                {Calendar.strftime(version.inserted_at, "%H:%M")}
              </span>
            </div>
            <div class="text-muted-foreground">
              {version.source}
              <%= if version.diff_summary do %>
                — {version.diff_summary}
              <% end %>
            </div>
            <div class="flex gap-1">
              <button
                phx-click="view_version"
                phx-value-number={version.version_number}
                class="text-primary hover:underline"
              >
                View
              </button>
              <%= if version.version_number != hd(@versions).version_number do %>
                <button
                  phx-click="rollback"
                  phx-value-number={version.version_number}
                  class="text-orange-600 hover:underline"
                  data-confirm={"Rollback to v#{version.version_number}? This creates a new version."}
                >
                  Restore
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_tab(%{tab: "test"} = assigns) do
    ~H"""
    <div class="space-y-3">
      <h3 class="text-xs font-semibold text-muted-foreground uppercase">Quick Actions</h3>
      <div class="space-y-1">
        <button
          phx-click="quick_test"
          phx-value-method="GET"
          class="w-full rounded border px-2 py-1 text-xs text-left hover:bg-accent"
        >
          Testar GET /
        </button>
        <button
          phx-click="quick_test"
          phx-value-method="POST"
          class="w-full rounded border px-2 py-1 text-xs text-left hover:bg-accent"
        >
          Testar POST / com exemplo
        </button>
        <button
          phx-click="generate_sample"
          class="w-full rounded border px-2 py-1 text-xs text-left hover:bg-accent"
        >
          Gerar dados de exemplo
        </button>
      </div>

      <h3 class="text-xs font-semibold text-muted-foreground uppercase mt-4">Snippets</h3>
      <div class="flex flex-wrap gap-1">
        <button
          :for={lang <- ~w(curl python javascript elixir ruby go)}
          phx-click="copy_snippet"
          phx-value-language={lang}
          class="rounded border px-2 py-0.5 text-xs hover:bg-accent"
        >
          {lang}
        </button>
      </div>

      <h3 class="text-xs font-semibold text-muted-foreground uppercase mt-4">History</h3>
      <%= if @test_history == [] do %>
        <p class="text-xs text-muted-foreground">No requests yet</p>
      <% else %>
        <div class="space-y-1 max-h-60 overflow-y-auto">
          <div
            :for={item <- @test_history}
            phx-click="load_history_item"
            phx-value-id={item.id}
            class="rounded border p-1.5 text-xs cursor-pointer hover:bg-accent flex items-center justify-between"
          >
            <div class="flex items-center gap-1">
              <span class="font-semibold">{item.method}</span>
              <span class="text-muted-foreground truncate max-w-[100px]">{item.path}</span>
            </div>
            <div class="flex items-center gap-1">
              <span class={[
                "inline-flex rounded-full px-1 py-0.5 text-[10px] font-semibold",
                history_status_color(item.response_status)
              ]}>
                {item.response_status}
              </span>
              <span class="text-muted-foreground">{item.duration_ms}ms</span>
            </div>
          </div>
        </div>
        <button
          phx-click="clear_history"
          class="text-xs text-destructive hover:underline"
          data-confirm="Limpar histórico de requests?"
        >
          Limpar histórico
        </button>
      <% end %>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("code_changed", %{"value" => new_code}, socket) do
    {:noreply,
     assign(socket,
       code: new_code,
       selected_version: nil,
       compile_success: false,
       compile_errors: nil
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket =
      if tab == "test" and not socket.assigns.history_loaded do
        history = Testing.list_test_requests(socket.assigns.api.id)
        assign(socket, test_history: history, history_loaded: true)
      else
        socket
      end

    {:noreply, assign(socket, tab: tab)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    save_version(socket, false)
  end

  @impl true
  def handle_event("save_and_compile", _params, socket) do
    save_version(socket, true)
  end

  @impl true
  def handle_event("view_version", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    version = Apis.get_version(socket.assigns.api.id, number)

    if version do
      {:noreply,
       socket
       |> assign(code: version.code, selected_version: version)
       |> push_editor_value(version.code)}
    else
      {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  @impl true
  def handle_event("clear_version_view", _params, socket) do
    api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)
    code = api.source_code || ""

    {:noreply,
     socket
     |> assign(code: code, selected_version: nil, api: api)
     |> push_editor_value(code)}
  end

  @impl true
  def handle_event("rollback", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)
    api = socket.assigns.api
    scope = socket.assigns.current_scope

    case Apis.rollback_to_version(api, number, scope.user.id) do
      {:ok, new_version} ->
        api = Apis.get_api(socket.assigns.org.id, api.id)

        # Recompile after rollback
        compile_result = compile_api(api, socket.assigns.org)

        {:noreply,
         socket
         |> assign(
           api: api,
           code: new_version.code,
           versions: Apis.list_versions(api.id),
           selected_version: nil,
           compile_errors: compile_result.errors,
           compile_success: compile_result.success
         )
         |> push_editor_value(new_version.code)
         |> put_flash(:info, "Rolled back to v#{number}")}

      {:error, :version_not_found} ->
        {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end

  # --- Test Tab Events ---

  @valid_methods ~w(GET POST PUT PATCH DELETE)
  @valid_request_tabs ~w(params headers body auth)
  @valid_response_tabs ~w(body headers)
  @valid_snippet_languages ~w(curl python javascript elixir ruby go)

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
    new_param = %{key: "", value: "", id: Ecto.UUID.generate()}
    {:noreply, assign(socket, test_params: socket.assigns.test_params ++ [new_param])}
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
    new_header = %{key: "", value: "", id: Ecto.UUID.generate()}
    {:noreply, assign(socket, test_headers: socket.assigns.test_headers ++ [new_header])}
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

    snippet =
      SnippetGenerator.generate(socket.assigns.api, String.to_atom(lang), request)

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: snippet})
     |> put_flash(:info, "Snippet #{lang} copiado!")}
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

  # --- Chat Events ---

  @impl true
  def handle_event("send_chat", %{"chat_input" => ""}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_chat", %{"chat_input" => message}, socket) do
    conversation = socket.assigns.chat_conversation

    # Persist user message
    case Conversations.append_message(conversation, "user", message) do
      {:ok, conversation} ->
        do_chat_request(socket, conversation, message)

      {:error, :too_many_messages} ->
        {:noreply, put_flash(socket, :error, friendly_llm_error(:too_many_messages))}

      {:error, reason} ->
        Logger.warning("Failed to append user message: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Falha ao enviar mensagem")}
    end
  end

  @impl true
  def handle_event("accept_edit", _params, socket) do
    case socket.assigns.pending_edit do
      nil ->
        {:noreply, socket}

      %{code: proposed_code, instruction: instruction} ->
        scope = socket.assigns.current_scope

        case Apis.create_version(socket.assigns.api, %{
               code: proposed_code,
               source: "chat_edit",
               prompt: instruction,
               created_by_id: scope.user.id
             }) do
          {:ok, _version} ->
            api = Apis.get_api(socket.assigns.org.id, socket.assigns.api.id)

            {:noreply,
             socket
             |> assign(
               api: api,
               code: proposed_code,
               versions: Apis.list_versions(api.id),
               pending_edit: nil
             )
             |> push_editor_value(proposed_code)
             |> put_flash(:info, "Mudança aceita e versão criada")}

          {:error, changeset} ->
            Logger.error("Failed to create chat_edit version: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Falha ao criar versão")}
        end
    end
  end

  @impl true
  def handle_event("reject_edit", _params, socket) do
    {:noreply, assign(socket, pending_edit: nil)}
  end

  @impl true
  def handle_event("quick_action", %{"text" => text}, socket) do
    {:noreply, assign(socket, chat_input: text)}
  end

  @impl true
  def handle_event("clear_conversation", _params, socket) do
    conversation = socket.assigns.chat_conversation

    case Conversations.clear_conversation(conversation) do
      {:ok, cleared} ->
        {:noreply,
         assign(socket,
           chat_conversation: cleared,
           chat_messages: [],
           pending_edit: nil
         )}

      {:error, changeset} ->
        Logger.error("Failed to clear conversation: #{inspect(changeset)}")
        {:noreply, put_flash(socket, :error, "Falha ao limpar conversa")}
    end
  end

  # --- Helpers ---

  defp do_chat_request(socket, conversation, message) do
    socket =
      socket
      |> assign(
        chat_conversation: conversation,
        chat_messages: conversation.messages,
        chat_loading: true,
        chat_input: ""
      )

    prompt =
      EditPrompts.build_edit_prompt(
        socket.assigns.code,
        message,
        conversation.messages
      )

    case Config.client().generate_text(prompt, system: EditPrompts.system_prompt()) do
      {:ok, %{content: response}} ->
        handle_llm_response(socket, conversation, response, message)

      {:error, reason} ->
        Logger.warning("LLM chat error for API #{socket.assigns.api.id}: #{inspect(reason)}")

        error_msg = friendly_llm_error(reason)

        {:ok, conversation} =
          Conversations.append_message(conversation, "assistant", error_msg)

        {:noreply,
         assign(socket,
           chat_conversation: conversation,
           chat_messages: conversation.messages,
           chat_loading: false
         )}
    end
  end

  defp save_version(socket, compile?) do
    api = socket.assigns.api
    scope = socket.assigns.current_scope
    code = socket.assigns.code

    # Fix 5: Skip save if code hasn't changed
    if code == (api.source_code || "") and not compile? do
      {:noreply, put_flash(socket, :info, "No changes to save")}
    else
      do_save_version(socket, api, scope, code, compile?)
    end
  end

  defp do_save_version(socket, api, scope, code, compile?) do
    case Apis.create_version(api, %{
           code: code,
           source: "manual_edit",
           created_by_id: scope.user.id
         }) do
      {:ok, version} ->
        api = Apis.get_api(socket.assigns.org.id, api.id)

        compile_result =
          if compile?,
            do: compile_api(api, socket.assigns.org),
            else: %{success: false, errors: nil}

        if compile?, do: update_version_status(version, compile_result)

        {:noreply,
         socket
         |> assign(
           api: api,
           versions: Apis.list_versions(api.id),
           compile_errors: compile_result.errors,
           compile_success: compile_result.success
         )
         |> put_flash(
           :info,
           if(compile? && compile_result.success, do: "Saved & compiled", else: "Saved")
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  defp update_version_status(version, compile_result) do
    alias Blackboex.Apis.ApiVersion

    status = if compile_result.success, do: "success", else: "error"
    errors = compile_result.errors || []

    Blackboex.Repo.update(
      ApiVersion.changeset(version, %{compilation_status: status, compilation_errors: errors})
    )
  end

  defp compile_api(api, org) do
    case Compiler.compile(api, api.source_code) do
      {:ok, module} ->
        Apis.update_api(api, %{status: "compiled"})

        try do
          Registry.register(api.id, module, username: org.slug, slug: api.slug)
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

        %{success: true, errors: nil}

      {:error, {:validation, reasons}} ->
        %{success: false, errors: reasons}

      {:error, {:compilation, reason}} ->
        %{success: false, errors: [reason]}
    end
  end

  # --- Task.async result handlers ---

  @impl true
  def handle_info({ref, result}, %{assigns: %{test_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, response} ->
        violations = validate_response(response, socket.assigns.api)

        # Persist to history
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
           test_error: "URL não permitida. Apenas /api/{username}/{slug}/* é aceito."
         )}

      {:error, :timeout} ->
        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Timeout: a requisição demorou demais."
         )}

      {:error, reason} ->
        Logger.warning("Test request failed: #{inspect(reason)}")

        {:noreply,
         assign(socket,
           test_loading: false,
           test_ref: nil,
           test_error: "Erro de conexão. Verifique se a API está compilada."
         )}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{test_ref: ref}} = socket) do
    {:noreply, assign(socket, test_loading: false, test_ref: nil)}
  end

  defp push_editor_value(socket, code) do
    editor_path = "api_#{socket.assigns.api.id}.ex"
    LiveMonacoEditor.set_value(socket, code, to: editor_path)
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

  defp default_test_body(api) do
    if api.example_request do
      Jason.encode!(api.example_request, pretty: true)
    else
      "{}"
    end
  end

  defp history_status_color(status) when status >= 200 and status < 300,
    do: "bg-green-50 text-green-700"

  defp history_status_color(status) when status >= 400 and status < 500,
    do: "bg-yellow-50 text-yellow-700"

  defp history_status_color(status) when status >= 500,
    do: "bg-red-50 text-red-700"

  defp history_status_color(_), do: "bg-muted text-muted-foreground"

  defp tab_label("info"), do: "Info"
  defp tab_label("versions"), do: "Versions"
  defp tab_label("test"), do: "Test"

  defp status_color("draft"), do: "border bg-muted text-muted-foreground"
  defp status_color("compiled"), do: "border-green-500 bg-green-50 text-green-700"
  defp status_color("published"), do: "border-blue-500 bg-blue-50 text-blue-700"
  defp status_color("archived"), do: "border-gray-500 bg-gray-50 text-gray-500"
  defp status_color(_), do: "border bg-muted text-muted-foreground"

  defp friendly_llm_error(:timeout), do: "A requisição demorou demais. Tente novamente."

  defp friendly_llm_error(:rate_limited),
    do: "Muitas requisições. Aguarde um momento e tente novamente."

  defp friendly_llm_error(:econnrefused),
    do: "Não foi possível conectar ao serviço de IA. Tente novamente mais tarde."

  defp friendly_llm_error(:too_many_messages),
    do: "Conversa muito longa. Use 'Nova conversa' para recomeçar."

  defp friendly_llm_error(reason) when is_binary(reason), do: "Erro: #{reason}"
  defp friendly_llm_error(reason), do: "Erro inesperado: #{inspect(reason)}"

  defp handle_llm_response(socket, conversation, response, instruction) do
    case EditPrompts.parse_response(response) do
      {:ok, proposed_code, explanation} ->
        # Persist assistant message
        {:ok, conversation} = Conversations.append_message(conversation, "assistant", explanation)

        diff = DiffEngine.compute_diff(socket.assigns.code, proposed_code)

        {:noreply,
         assign(socket,
           chat_conversation: conversation,
           chat_messages: conversation.messages,
           chat_loading: false,
           pending_edit: %{
             code: proposed_code,
             diff: diff,
             explanation: explanation,
             instruction: instruction
           }
         )}

      {:error, :no_code_found} ->
        {:ok, conversation} =
          Conversations.append_message(
            conversation,
            "assistant",
            response
          )

        {:noreply,
         assign(socket,
           chat_conversation: conversation,
           chat_messages: conversation.messages,
           chat_loading: false
         )}
    end
  end
end
