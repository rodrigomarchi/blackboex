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
           test_body: ~s({"n": 5}),
           test_result: nil,
           chat_messages: conversation.messages,
           chat_input: "",
           chat_loading: false,
           chat_conversation: conversation,
           pending_edit: nil
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

          <%!-- Editor Panel (50%) --%>
          <div class="col-span-6 rounded-lg border bg-card text-card-foreground shadow-sm">
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
      <form phx-submit="test_api" phx-change="update_test_body" class="space-y-2">
        <label class="text-xs text-muted-foreground">Request body (JSON)</label>
        <textarea
          name="test_body"
          rows="3"
          class="w-full rounded-md border bg-background px-2 py-1 text-xs font-mono"
          placeholder={~s({"n": 5})}
        >{@test_body}</textarea>
        <div class="flex gap-1">
          <button type="submit" class="rounded border px-2 py-1 text-xs hover:bg-accent">
            POST
          </button>
          <button
            type="button"
            phx-click="test_api_get"
            class="rounded border px-2 py-1 text-xs hover:bg-accent"
          >
            GET
          </button>
        </div>
      </form>
      <%= if @test_result do %>
        <pre class="overflow-x-auto rounded bg-muted p-2 text-xs"><code>{@test_result}</code></pre>
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

  defp run_test(socket, method, body) do
    api = socket.assigns.api

    case ensure_module(api, socket.assigns.org) do
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
        {:noreply, assign(socket, test_result: "Failed: #{inspect(reason)}")}
    end
  end

  defp ensure_module(api, org) do
    case Registry.lookup(api.id) do
      {:ok, _} = found ->
        found

      {:error, :not_found} ->
        with {:ok, module} <- Compiler.compile(api, api.source_code) do
          try do
            Registry.register(api.id, module, username: org.slug, slug: api.slug)
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end

          {:ok, module}
        end
    end
  end

  defp build_test_conn(:get, _body) do
    Plug.Test.conn(:get, "/") |> Plug.Conn.put_req_header("content-type", "application/json")
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
    body =
      case Jason.decode(conn.resp_body) do
        {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
        {:error, _} -> conn.resp_body
      end

    "HTTP #{conn.status}\n#{body}"
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
