defmodule BlackboexWeb.ApiLive.Edit.InfoLive do
  @moduledoc false

  use BlackboexWeb, :live_view

  import BlackboexWeb.ApiLive.Edit.EditorShell
  import BlackboexWeb.ApiLive.Edit.Helpers, only: [count_lines: 1, format_json: 1]
  import BlackboexWeb.Components.Shared.CodeEditorField
  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.Components.Shared.StatMini
  import BlackboexWeb.Components.UI.InlineInput
  import BlackboexWeb.Components.UI.InlineTextarea
  import BlackboexWeb.Components.Label

  alias Blackboex.Apis
  alias BlackboexWeb.ApiLive.Edit.Shared

  @command_palette_events ~w(toggle_command_palette close_panels command_palette_search
    command_palette_navigate command_palette_exec command_palette_exec_first)

  @impl true
  def mount(params, _session, socket) do
    case Shared.load_api(socket, params) do
      {:ok, socket} ->
        api = socket.assigns.api
        files = Apis.list_files(api.id)

        source_content =
          files |> Enum.filter(&(&1.file_type == "source")) |> Enum.map_join("\n\n", & &1.content)

        test_content =
          files |> Enum.filter(&(&1.file_type == "test")) |> Enum.map_join("\n\n", & &1.content)

        {:ok,
         assign(socket,
           source_lines: count_lines(source_content),
           test_lines: count_lines(test_content),
           confirm: nil
         )}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.editor_shell {shared_shell_assigns(assigns)} active_tab="info">
      <div class="p-4 overflow-y-auto h-full max-w-3xl space-y-6">
        <.section_heading level="h2" compact>API Information</.section_heading>

        <%!-- General --%>
        <div>
          <.section_heading
            level="h3"
            icon="hero-cog-6-tooth"
            icon_class="size-3.5 text-slate-400"
            variant="label"
          >
            General
          </.section_heading>
          <.form :let={_f} for={%{}} as={:info} phx-submit="update_info" class="space-y-3">
            <div>
              <.label class="text-xs font-medium">Name</.label>
              <.inline_input
                type="text"
                name="name"
                value={@api.name}
                maxlength="200"
                class="mt-1 rounded-md px-3 py-2"
              />
            </div>
            <div>
              <.label class="text-xs font-medium">Description</.label>
              <.inline_textarea
                name="description"
                rows="3"
                maxlength="10000"
                value={@api.description}
                class="mt-1 rounded-md px-3 py-2"
              />
            </div>
            <div class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span class="text-muted-caption">Slug</span>
                <p class="font-mono">{@api.slug}</p>
              </div>
              <div>
                <span class="text-muted-caption">Template</span>
                <p>{@api.template_type}</p>
              </div>
              <div>
                <span class="text-muted-caption">Created</span>
                <p>{Calendar.strftime(@api.inserted_at, "%Y-%m-%d %H:%M")}</p>
              </div>
              <div>
                <span class="text-muted-caption">Last modified</span>
                <p>{Calendar.strftime(@api.updated_at, "%Y-%m-%d %H:%M")}</p>
              </div>
            </div>
            <.button type="submit" variant="primary" size="sm">
              <.icon name="hero-check" class="mr-1.5 size-3.5" /> Save Changes
            </.button>
          </.form>
        </div>

        <%!-- Code Stats --%>
        <div>
          <.section_heading
            level="h3"
            icon="hero-code-bracket"
            icon_class="size-3.5 text-accent-purple"
            variant="label"
          >
            Code Stats
          </.section_heading>
          <div class="grid grid-cols-4 gap-3">
            <.stat_mini
              value={@source_lines}
              label="Source Lines"
              icon="hero-code-bracket-mini"
              icon_class="text-accent-purple"
            />
            <.stat_mini
              value={@test_lines}
              label="Test Lines"
              icon="hero-beaker-mini"
              icon_class="text-accent-emerald"
            />
            <.stat_mini
              value={length(@versions)}
              label="Versions"
              icon="hero-clock-mini"
              icon_class="text-accent-amber"
            />
            <.stat_mini
              value={if @versions != [], do: "v#{hd(@versions).version_number}", else: "-"}
              label="Latest"
              icon="hero-tag-mini"
              icon_class="text-accent-blue"
            />
          </div>
        </div>

        <%!-- Request/Response Schema --%>
        <%= if @api.param_schema || @api.example_request || @api.example_response do %>
          <div>
            <.section_heading
              level="h3"
              icon="hero-document-text"
              icon_class="size-3.5 text-accent-blue"
              class="mb-3"
              heading_class="text-xs font-semibold text-muted-foreground uppercase"
            >
              Request/Response Schema
            </.section_heading>
            <div class="space-y-3">
              <%= if @api.param_schema do %>
                <div>
                  <span class="text-xs font-medium">Param Schema</span>
                  <.code_editor_field
                    id="info-param-schema"
                    value={format_json(@api.param_schema)}
                    max_height="max-h-60"
                    class="mt-1"
                  />
                </div>
              <% end %>
              <div class="grid grid-cols-2 gap-3">
                <%= if @api.example_request do %>
                  <div>
                    <span class="text-xs font-medium">Example Request</span>
                    <.code_editor_field
                      id="info-example-request"
                      value={format_json(@api.example_request)}
                      max_height="max-h-60"
                      class="mt-1"
                    />
                  </div>
                <% end %>
                <%= if @api.example_response do %>
                  <div>
                    <span class="text-xs font-medium">Example Response</span>
                    <.code_editor_field
                      id="info-example-response"
                      value={format_json(@api.example_response)}
                      max_height="max-h-60"
                      class="mt-1"
                    />
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Danger Zone --%>
        <div>
          <.section_heading
            level="h3"
            icon="hero-exclamation-triangle"
            icon_class="size-3.5 text-accent-red"
            variant="label"
          >
            Danger Zone
          </.section_heading>
          <div class="rounded-lg border border-destructive/30 p-4 flex items-center justify-between">
            <div>
              <p class="text-sm font-medium">Archive this API</p>
              <p class="text-muted-caption">
                Removes from active list. Published APIs will be unpublished first.
              </p>
            </div>
            <.button
              phx-click="request_confirm"
              phx-value-action="archive_api"
              variant="outline"
              size="sm"
              class="border-destructive text-destructive hover:bg-destructive/10"
            >
              <.icon name="hero-archive-box" class="mr-1.5 size-3.5" /> Archive API
            </.button>
          </div>
        </div>
      </div>

      <.confirm_dialog
        :if={@confirm}
        title={@confirm.title}
        description={@confirm.description}
        variant={@confirm[:variant] || :warning}
        confirm_label={@confirm[:confirm_label] || "Confirm"}
      />
    </.editor_shell>
    """
  end

  @impl true
  def handle_event(event, params, socket) when event in @command_palette_events do
    Shared.handle_command_palette(event, params, socket)
  end

  # ── Confirm Dialog ────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = build_confirm(params["action"], params)
    {:noreply, assign(socket, confirm: confirm)}
  end

  @impl true
  def handle_event("dismiss_confirm", _params, socket) do
    {:noreply, assign(socket, confirm: nil)}
  end

  @impl true
  def handle_event("execute_confirm", _params, socket) do
    case socket.assigns.confirm do
      nil ->
        {:noreply, socket}

      %{event: event, meta: meta} ->
        handle_event(event, meta, assign(socket, confirm: nil))
    end
  end

  def handle_event("update_info", %{"name" => name, "description" => description}, socket) do
    case Apis.update_api(socket.assigns.api, %{
           name: String.trim(name),
           description: String.trim(description)
         }) do
      {:ok, api} ->
        {:noreply,
         socket
         |> assign(api: api, page_title: "Edit: #{api.name}")
         |> put_flash(:info, "API info updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update API info")}
    end
  end

  def handle_event("archive_api", _params, socket) do
    org = socket.assigns.org

    case Apis.get_api(org.id, socket.assigns.api.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "API not found")}

      api ->
        if api.status == "published", do: Apis.unpublish(api)
        Apis.update_api(api, %{status: "archived"})

        {:noreply,
         socket
         |> put_flash(:info, "API archived")
         |> push_navigate(to: ~p"/apis")}
    end
  end

  def handle_event("copy_url", _params, socket) do
    url = "/api/#{socket.assigns.org.slug}/#{socket.assigns.api.slug}"
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  # ── Private ───────────────────────────────────────────────────────────

  defp build_confirm("archive_api", _params) do
    %{
      title: "Archive this API?",
      description:
        "Published APIs will be unpublished and the API will be archived. This cannot be undone.",
      variant: :danger,
      confirm_label: "Archive",
      event: "archive_api",
      meta: %{}
    }
  end

  defp build_confirm(_, _), do: nil

  @spec shared_shell_assigns(map()) :: map()
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
