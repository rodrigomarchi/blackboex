defmodule BlackboexWeb.Components.SidebarTreeComponent do
  @moduledoc """
  Live component that hosts the unified Org → Project → Type → Item navigation tree.

  Renders projects for the current organization with expandable group nodes
  (Pages, APIs, Flows, Playgrounds) and lazy-loaded leaf items.

  ## Assigns

    * `:id` (string, required) — component DOM id
    * `:current_scope` (map | nil) — scope with `:user`, `:organization`, `:project` fields
    * `:current_path` (string) — current URL path; used for active-state detection and auto-expand
    * `:collapsed` (boolean) — ignored (sidebar hides us when collapsed); accepted for safety

  ## Events handled

    * `"expand_node"` — `%{"type" => type, "id" => id}` — expands a node, loads children lazily
    * `"collapse_node"` — `%{"type" => type, "id" => id}` — collapses a node
    * `"open_create_modal"` — `%{"type" => type, "project-id" => pid}` (+ optional `"parent-id"`) — opens create-resource modal
    * `"close_create_modal"` — closes create-resource modal
    * `"create_resource"` — `%{"type" => type, "project_id" => pid, "name" => name}` — creates resource and navigates

  ## ID key convention for `:expanded` and `:tree_children`

    * `"project:<uuid>"` — project row expanded (shows 4 group nodes)
    * `"pages:<project_uuid>"` — pages group expanded
    * `"apis:<project_uuid>"` — apis group expanded
    * `"flows:<project_uuid>"` — flows group expanded
    * `"playgrounds:<project_uuid>"` — playgrounds group expanded

  Expanded state is persisted asynchronously to `Accounts.update_user_preference/3`
  at path `["sidebar_tree", "expanded"]`.

  ## Auto-expand

  When `:current_path` matches `/orgs/:slug/projects/:slug[/type]`, the component
  automatically expands the matching project (and group if type is present), merging
  with saved preferences.

  ## Create-resource modal

  `:create_modal` assign holds `nil` (closed) or `%{type: string, project_id: string,
  parent_id: string | nil}`. Type is always a singular resource type string:
  `"api"`, `"flow"`, `"page"`, `"playground"`. Incoming group names (e.g. `"apis"`)
  are normalised to singular before storing.

  ## Security

  Type-to-policy-action mapping is a compile-time whitelist (`@create_actions`).
  Unknown types return `{:error, :forbidden}` without touching any atom table.
  Cross-org project_id is rejected by domain context IDOR checks (Fase 0).
  """

  use BlackboexWeb, :live_component

  import BlackboexWeb.Components.Modal

  alias Blackboex.{Accounts, Apis, Flows, Pages, Playgrounds, Projects}
  alias Blackboex.Policy

  # Whitelist map: resource type string → LetMe policy action atom.
  # Never use String.to_atom/1 on user input — use Map.get/2 on this map.
  @create_actions %{
    "api" => :api_create,
    "flow" => :flow_create,
    "page" => :page_create,
    "playground" => :playground_create
  }

  @update_actions %{
    "api" => :api_update,
    "flow" => :flow_update,
    "page" => :page_update,
    "playground" => :playground_update
  }

  @delete_actions %{
    "api" => :api_delete,
    "flow" => :flow_delete,
    "page" => :page_delete,
    "playground" => :playground_delete
  }

  # Normalises group-node type strings ("apis") to singular resource type ("api").
  @singular %{
    "apis" => "api",
    "flows" => "flow",
    "pages" => "page",
    "playgrounds" => "playground"
  }

  # Normalises singular type to group key prefix used in tree_children cache.
  @plural %{
    "api" => "apis",
    "flow" => "flows",
    "page" => "pages",
    "playground" => "playgrounds"
  }

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       projects: [],
       expanded: [],
       tree_children: %{},
       create_modal: nil,
       create_error: nil,
       open_menu_id: nil,
       renaming: nil,
       rename_error: nil,
       delete_modal: nil,
       move_error: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    scope = assigns[:current_scope]
    projects = load_projects(scope)
    expanded_prefs = load_expanded_prefs(scope)
    auto_expanded = auto_expand_from_path(assigns[:current_path], projects)
    expanded = Enum.uniq(expanded_prefs ++ auto_expanded)

    # Allow test injection of expanded/tree_children via assigns (assign_new respects existing)
    socket =
      socket
      |> assign(assigns)
      |> assign(:projects, projects)
      |> assign(:expanded, expanded)
      |> assign_new(:tree_children, fn -> %{} end)
      |> assign_new(:create_modal, fn -> nil end)

    # If caller provided expanded or tree_children directly (e.g. in render_component tests),
    # honour them over what we computed.
    socket =
      if Map.has_key?(assigns, :expanded) do
        assign(socket, :expanded, assigns.expanded)
      else
        socket
      end

    socket =
      if Map.has_key?(assigns, :tree_children) do
        assign(socket, :tree_children, assigns.tree_children)
      else
        assign(
          socket,
          :tree_children,
          preload_expanded_children(socket.assigns.tree_children, expanded)
        )
      end

    socket =
      if Map.has_key?(assigns, :create_modal) do
        assign(socket, :create_modal, assigns.create_modal)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav
      data-testid="sidebar-tree"
      id={@id}
      aria-label="Workspace navigation"
      class="py-1"
      phx-hook="SidebarTreeDnD"
      phx-target={@myself}
    >
      <%= if @projects == [] do %>
        <p class="px-3 py-2 text-xs text-muted-foreground">No projects yet.</p>
      <% else %>
        <ul role="tree" class="space-y-0.5 px-2">
          <li :for={entry <- @projects} role="treeitem">
            <.project_node
              entry={entry}
              expanded={@expanded}
              tree_children={@tree_children}
              current_path={@current_path}
              current_scope={@current_scope}
              open_menu_id={@open_menu_id}
              renaming={@renaming}
              rename_error={@rename_error}
              myself={@myself}
            />
          </li>
        </ul>
      <% end %>

      <.modal
        :if={@create_modal != nil}
        show={true}
        on_close="close_create_modal"
        title={"Create #{modal_title(@create_modal)}"}
      >
        <.create_resource_form create_modal={@create_modal} myself={@myself} error={@create_error} />
      </.modal>

      <.modal
        :if={@delete_modal != nil}
        show={true}
        on_close="close_delete_modal"
        title={"Delete #{@delete_modal && @delete_modal.name}"}
      >
        <.delete_confirm_form delete_modal={@delete_modal} myself={@myself} />
      </.modal>
    </nav>
    """
  end

  @impl true
  def handle_event("expand_node", %{"type" => type, "id" => id}, socket) do
    key = "#{type}:#{id}"

    if key in socket.assigns.expanded do
      {:noreply, socket}
    else
      new_expanded = [key | socket.assigns.expanded]
      new_children = load_children(socket.assigns.tree_children, type, id)
      persist_expanded_async(socket.assigns.current_scope, new_expanded)
      {:noreply, assign(socket, expanded: new_expanded, tree_children: new_children)}
    end
  end

  def handle_event("collapse_node", %{"type" => type, "id" => id}, socket) do
    key = "#{type}:#{id}"
    new_expanded = List.delete(socket.assigns.expanded, key)
    persist_expanded_async(socket.assigns.current_scope, new_expanded)
    {:noreply, assign(socket, :expanded, new_expanded)}
  end

  def handle_event("open_create_modal", params, socket) do
    raw_type = params["type"]
    type = Map.get(@singular, raw_type, raw_type)

    modal = %{
      type: type,
      project_id: params["project-id"],
      parent_id: params["parent-id"]
    }

    {:noreply, assign(socket, create_modal: modal, create_error: nil)}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, create_modal: nil, create_error: nil)}
  end

  def handle_event(
        "create_resource",
        %{"type" => type, "project_id" => project_id, "name" => name} = params,
        socket
      ) do
    scope = socket.assigns.current_scope
    parent_id = params["parent_id"]
    project = find_project(socket.assigns.projects, project_id)

    with :ok <- authorize_create(type, scope),
         {:ok, resource} <- do_create(type, scope, project_id, parent_id, name) do
      url = canonical_url_for_create(type, scope, project, resource)
      {:noreply, socket |> assign(:create_modal, nil) |> push_navigate(to: url)}
    else
      {:error, :forbidden} ->
        {:noreply,
         assign(socket, :create_error, "You don't have permission to create this resource.")}

      {:error, %Ecto.Changeset{} = cs} ->
        error_msg = format_changeset_errors(cs)
        {:noreply, assign(socket, :create_error, error_msg)}

      {:error, :limit_exceeded, _meta} ->
        {:noreply, assign(socket, :create_error, "Plan limit reached. Upgrade to create more.")}
    end
  end

  def handle_event("open_item_menu", %{"type" => type, "id" => id}, socket) do
    menu_id = "#{type}:#{id}"

    new_menu_id =
      if socket.assigns.open_menu_id == menu_id, do: nil, else: menu_id

    {:noreply, assign(socket, open_menu_id: new_menu_id)}
  end

  def handle_event("close_item_menu", _params, socket) do
    {:noreply, assign(socket, :open_menu_id, nil)}
  end

  def handle_event("start_rename", %{"type" => type, "id" => id}, socket) do
    item = find_item_in_cache(socket.assigns.tree_children, type, id)

    case item do
      nil ->
        {:noreply, assign(socket, open_menu_id: nil)}

      _ ->
        {:noreply,
         assign(socket,
           renaming: %{type: type, id: id, value: display_name(type, item)},
           open_menu_id: nil,
           rename_error: nil
         )}
    end
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, renaming: nil, rename_error: nil)}
  end

  def handle_event("submit_rename", params, socket) do
    renaming = socket.assigns.renaming
    raw_type = params["type"] || (renaming && renaming.type)
    type = singular_type(raw_type || "")
    id = params["_id"] || (renaming && renaming.id)
    new_name = String.trim(params["value"] || "")

    if new_name == "" do
      {:noreply, assign(socket, :rename_error, "Name can't be blank")}
    else
      do_submit_rename(socket, type, id, new_name)
    end
  end

  def handle_event("open_delete_modal", %{"type" => type, "id" => id}, socket) do
    item = find_item_in_cache(socket.assigns.tree_children, type, id)

    case item do
      nil ->
        {:noreply, assign(socket, open_menu_id: nil)}

      _ ->
        modal = %{
          type: type,
          id: id,
          name: display_name(type, item),
          confirm_text: ""
        }

        {:noreply, assign(socket, delete_modal: modal, open_menu_id: nil)}
    end
  end

  def handle_event("update_delete_confirm", %{"confirm" => text}, socket) do
    modal = Map.put(socket.assigns.delete_modal, :confirm_text, text)
    {:noreply, assign(socket, :delete_modal, modal)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :delete_modal, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    %{type: type, id: id, name: name, confirm_text: confirm} = socket.assigns.delete_modal

    if confirm == name do
      do_confirmed_delete(socket, type, id)
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_node", params, socket) do
    with {:ok, rules} <- parse_move(params),
         {:ok, resource} <- authorize_move(rules, socket.assigns.current_scope),
         {:ok, updated} <- apply_move(rules, resource) do
      # Pass old_project_id from the pre-move resource so refresh can clear the source group
      old_project_id = resource.project_id

      {:noreply,
       socket
       |> assign(:move_error, nil)
       |> refresh_tree_after_move(rules, updated, old_project_id)}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:move_error, humanize_move_error(reason))
         |> push_event("sidebar_tree:rollback", %{reason: humanize_move_error(reason)})}
    end
  end

  # ── Private function components ────────────────────────────────────────────

  attr :entry, :map, required: true
  attr :expanded, :list, required: true
  attr :tree_children, :map, required: true
  attr :current_path, :string, required: true
  attr :current_scope, :map, required: true
  attr :open_menu_id, :string, default: nil
  attr :renaming, :map, default: nil
  attr :rename_error, :string, default: nil
  attr :myself, :any, required: true

  defp project_node(assigns) do
    project = assigns.entry.project
    key = "project:#{project.id}"
    is_expanded = key in assigns.expanded
    assigns = assign(assigns, project: project, project_key: key, is_expanded: is_expanded)

    ~H"""
    <div class="flex flex-col">
      <button
        type="button"
        class="flex w-full items-center gap-2 rounded px-2 py-1 text-sm hover:bg-muted text-left"
        phx-click={if @is_expanded, do: "collapse_node", else: "expand_node"}
        phx-value-type="project"
        phx-value-id={@project.id}
        phx-target={@myself}
      >
        <.icon
          name={if @is_expanded, do: "hero-chevron-down-micro", else: "hero-chevron-right-micro"}
          class="size-3 shrink-0 text-muted-foreground"
        />
        <.icon name="hero-folder-micro" class="size-3.5 shrink-0 text-muted-foreground" />
        <span class="truncate font-medium">{@project.name}</span>
      </button>

      <ul :if={@is_expanded} class="ml-3 space-y-0.5" role="group">
        <li>
          <.project_action_link
            icon="hero-cog-6-tooth-micro"
            label="Settings"
            url={project_action_url(@current_scope, @project, "settings")}
            current_path={@current_path}
          />
        </li>
        <li>
          <.group_node
            type="pages"
            label="Pages"
            count={@entry.pages_count}
            project={@project}
            expanded={@expanded}
            tree_children={@tree_children}
            current_path={@current_path}
            current_scope={@current_scope}
            open_menu_id={@open_menu_id}
            renaming={@renaming}
            rename_error={@rename_error}
            myself={@myself}
          />
        </li>
        <li>
          <.group_node
            type="apis"
            label="APIs"
            count={@entry.apis_count}
            project={@project}
            expanded={@expanded}
            tree_children={@tree_children}
            current_path={@current_path}
            current_scope={@current_scope}
            open_menu_id={@open_menu_id}
            renaming={@renaming}
            rename_error={@rename_error}
            myself={@myself}
          />
        </li>
        <li>
          <.group_node
            type="playgrounds"
            label="Playgrounds"
            count={@entry.playgrounds_count}
            project={@project}
            expanded={@expanded}
            tree_children={@tree_children}
            current_path={@current_path}
            current_scope={@current_scope}
            open_menu_id={@open_menu_id}
            renaming={@renaming}
            rename_error={@rename_error}
            myself={@myself}
          />
        </li>
        <li>
          <.group_node
            type="flows"
            label="Flows"
            count={@entry.flows_count}
            project={@project}
            expanded={@expanded}
            tree_children={@tree_children}
            current_path={@current_path}
            current_scope={@current_scope}
            open_menu_id={@open_menu_id}
            renaming={@renaming}
            rename_error={@rename_error}
            myself={@myself}
          />
        </li>
      </ul>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :project, :map, required: true
  attr :expanded, :list, required: true
  attr :tree_children, :map, required: true
  attr :current_path, :string, required: true
  attr :current_scope, :map, required: true
  attr :open_menu_id, :string, default: nil
  attr :renaming, :map, default: nil
  attr :rename_error, :string, default: nil
  attr :myself, :any, required: true

  defp group_node(assigns) do
    key = "#{assigns.type}:#{assigns.project.id}"
    is_expanded = key in assigns.expanded
    children = Map.get(assigns.tree_children, key, [])
    assigns = assign(assigns, group_key: key, is_expanded: is_expanded, children: children)

    ~H"""
    <div class="group flex flex-col">
      <div class="relative flex items-center">
        <button
          type="button"
          class="flex flex-1 items-center gap-1.5 rounded px-2 py-0.5 text-xs hover:bg-muted text-left text-muted-foreground"
          phx-click={if @is_expanded, do: "collapse_node", else: "expand_node"}
          phx-value-type={@type}
          phx-value-id={@project.id}
          phx-target={@myself}
          data-group-label={@label}
        >
          <.icon
            name={if @is_expanded, do: "hero-chevron-down-micro", else: "hero-chevron-right-micro"}
            class="size-2.5 shrink-0"
          />
          <.icon name={type_icon(@type)} class={"size-3 shrink-0 #{type_color(@type)}"} />
          <span class="truncate">{@label}</span>
          <span
            :if={@count > 0}
            class="ml-auto text-2xs tabular-nums text-muted-foreground/70 group-hover:opacity-0"
          >
            {@count}
          </span>
        </button>

        <button
          type="button"
          class="absolute right-1 top-1/2 -translate-y-1/2 hidden group-hover:inline-flex items-center justify-center rounded px-1 py-0.5 text-xs text-muted-foreground hover:bg-background hover:text-foreground"
          phx-click="open_create_modal"
          phx-value-type={@type}
          phx-value-project-id={@project.id}
          phx-target={@myself}
          aria-label={"Create #{@label}"}
        >
          +
        </button>
      </div>

      <ul
        :if={@is_expanded}
        class="ml-3 space-y-0.5"
        role="group"
        data-tree-list
        data-parent-type={@type}
        data-parent-id={@project.id}
      >
        <li :if={@children == []} class="px-2 py-0.5 text-xs text-muted-foreground/60 italic">
          No items
        </li>
        <%= if @type == "pages" do %>
          <.page_tree_node
            :for={node <- @children}
            node={node}
            project={@project}
            current_path={@current_path}
            current_scope={@current_scope}
            open_menu_id={@open_menu_id}
            renaming={@renaming}
            rename_error={@rename_error}
            myself={@myself}
          />
        <% else %>
          <li
            :for={item <- @children}
            role="treeitem"
            data-tree-item
            data-node-id={item.id}
            data-node-type={singular_type(@type)}
          >
            <.leaf_node
              type={@type}
              item={item}
              project={@project}
              current_path={@current_path}
              current_scope={@current_scope}
              open_menu_id={@open_menu_id}
              renaming={@renaming}
              rename_error={@rename_error}
              myself={@myself}
            />
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :project, :map, required: true
  attr :current_path, :string, required: true
  attr :current_scope, :map, required: true
  attr :open_menu_id, :string, default: nil
  attr :renaming, :map, default: nil
  attr :rename_error, :string, default: nil
  attr :myself, :any, required: true

  defp page_tree_node(assigns) do
    assigns =
      assign(assigns,
        page: assigns.node.page,
        children: assigns.node.children || []
      )

    ~H"""
    <li
      role="treeitem"
      data-tree-item
      data-node-id={@page.id}
      data-node-type="page"
    >
      <.leaf_node
        type="pages"
        item={@page}
        project={@project}
        current_path={@current_path}
        current_scope={@current_scope}
        open_menu_id={@open_menu_id}
        renaming={@renaming}
        rename_error={@rename_error}
        myself={@myself}
      />

      <ul
        :if={@children != []}
        class="ml-3 space-y-0.5"
        role="group"
        data-tree-list
        data-parent-type="page"
        data-parent-id={@page.id}
      >
        <.page_tree_node
          :for={child <- @children}
          node={child}
          project={@project}
          current_path={@current_path}
          current_scope={@current_scope}
          open_menu_id={@open_menu_id}
          renaming={@renaming}
          rename_error={@rename_error}
          myself={@myself}
        />
      </ul>
    </li>
    """
  end

  attr :type, :string, required: true
  attr :item, :map, required: true
  attr :project, :map, required: true
  attr :current_path, :string, required: true
  attr :current_scope, :map, required: true
  attr :open_menu_id, :string, default: nil
  attr :renaming, :map, default: nil
  attr :rename_error, :string, default: nil
  attr :myself, :any, required: true

  defp leaf_node(assigns) do
    url = canonical_url(assigns.type, assigns.current_scope, assigns.project, assigns.item)
    label = item_label(assigns.type, assigns.item)
    is_active = active_path?(assigns.current_path, url)
    singular = singular_type(assigns.type)
    menu_id = "#{singular}:#{assigns.item.id}"
    is_menu_open = assigns.open_menu_id == menu_id

    is_renaming =
      assigns.renaming != nil and
        assigns.renaming.type == singular and
        assigns.renaming.id == assigns.item.id

    assigns =
      assign(assigns,
        url: url,
        label: label,
        is_active: is_active,
        singular: singular,
        menu_id: menu_id,
        is_menu_open: is_menu_open,
        is_renaming: is_renaming
      )

    ~H"""
    <div class="group flex items-center relative">
      <%= if @is_renaming do %>
        <form
          phx-submit="submit_rename"
          phx-target={@myself}
          class="flex-1 flex items-center gap-1 px-1"
        >
          <input type="hidden" name="type" value={@singular} />
          <input type="hidden" name="_id" value={@item.id} />
          <input
            type="text"
            name="value"
            value={@renaming.value}
            autofocus
            class="flex-1 rounded border bg-background px-1.5 py-0.5 text-xs focus:outline-none focus:ring-1 focus:ring-ring"
          />
        </form>
        <button
          type="button"
          phx-click="cancel_rename"
          phx-target={@myself}
          class="shrink-0 px-1 py-0.5 text-xs text-muted-foreground hover:text-foreground"
          aria-label="Cancel rename"
        >
          ✕
        </button>
        <p
          :if={@rename_error}
          class="absolute top-full left-0 z-10 text-xs text-destructive bg-background px-1 rounded shadow"
        >
          {@rename_error}
        </p>
      <% else %>
        <.link
          navigate={@url}
          class={[
            "flex flex-1 items-center gap-1.5 rounded px-2 py-0.5 text-xs truncate",
            if(@is_active,
              do: "bg-accent text-accent-foreground font-medium",
              else: "text-muted-foreground hover:bg-muted hover:text-foreground"
            )
          ]}
          aria-current={if @is_active, do: "page", else: nil}
        >
          <.icon name={type_icon(@type)} class={"size-3 shrink-0 #{type_color(@type)}"} />
          <span class="truncate">{@label}</span>
        </.link>

        <div class={[
          "absolute right-1 top-1/2 -translate-y-1/2 items-center gap-0.5",
          if(@is_menu_open, do: "flex", else: "hidden group-hover:flex")
        ]}>
          <button
            :if={@type == "pages"}
            type="button"
            class="inline-flex items-center justify-center rounded px-1 py-0.5 text-xs text-muted-foreground hover:bg-background hover:text-foreground"
            phx-click="open_create_modal"
            phx-value-type="pages"
            phx-value-project-id={@project.id}
            phx-value-parent-id={@item.id}
            phx-target={@myself}
            aria-label="Create sub-page"
          >
            +
          </button>

          <%!-- Context menu trigger --%>
          <div class="relative">
            <button
              type="button"
              phx-click="open_item_menu"
              phx-value-type={@singular}
              phx-value-id={@item.id}
              phx-target={@myself}
              class="inline-flex items-center justify-center rounded px-1 py-0.5 text-xs text-muted-foreground hover:bg-background hover:text-foreground"
              aria-label="Item actions"
            >
              ⋯
            </button>

            <div
              :if={@is_menu_open}
              role="menu"
              class="absolute right-0 z-20 mt-1 min-w-[8rem] rounded border bg-popover p-1 shadow-md"
            >
              <button
                role="menuitem"
                type="button"
                phx-click="start_rename"
                phx-value-type={@singular}
                phx-value-id={@item.id}
                phx-target={@myself}
                class="w-full rounded px-2 py-1 text-left text-xs hover:bg-muted"
              >
                Rename
              </button>
              <button
                role="menuitem"
                type="button"
                phx-click="open_delete_modal"
                phx-value-type={@singular}
                phx-value-id={@item.id}
                phx-target={@myself}
                class="w-full rounded px-2 py-1 text-left text-xs text-destructive hover:bg-muted"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :create_modal, :map, required: true
  attr :myself, :any, required: true
  attr :error, :string, default: nil

  defp create_resource_form(assigns) do
    ~H"""
    <form phx-submit="create_resource" phx-target={@myself}>
      <input type="hidden" name="type" value={@create_modal.type} />
      <input type="hidden" name="project_id" value={@create_modal.project_id} />
      <input
        :if={@create_modal.parent_id}
        type="hidden"
        name="parent_id"
        value={@create_modal.parent_id}
      />

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium mb-1.5">
            {form_field_label(@create_modal.type)}
          </label>
          <input
            type="text"
            name="name"
            required
            autofocus
            placeholder={form_field_placeholder(@create_modal.type)}
            class="w-full rounded-md border bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
        </div>

        <p :if={@error} class="text-sm text-destructive" role="alert">{@error}</p>

        <div class="flex justify-end gap-2 pt-2">
          <.button type="button" variant="outline" phx-click="close_create_modal" phx-target={@myself}>
            Cancel
          </.button>
          <.button type="submit" variant="primary">
            Create
          </.button>
        </div>
      </div>
    </form>
    """
  end

  attr :delete_modal, :map, required: true
  attr :myself, :any, required: true

  defp delete_confirm_form(assigns) do
    ~H"""
    <div class="space-y-4">
      <p class="text-sm text-muted-foreground">
        This cannot be undone. Type <code class="font-mono font-semibold">{@delete_modal.name}</code>
        below to confirm.
      </p>

      <form phx-change="update_delete_confirm" phx-target={@myself}>
        <input
          type="text"
          name="confirm"
          value={@delete_modal.confirm_text}
          autofocus
          placeholder={@delete_modal.name}
          class="w-full rounded-md border bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
      </form>

      <div class="flex justify-end gap-2 pt-2">
        <.button
          type="button"
          variant="outline"
          phx-click="close_delete_modal"
          phx-target={@myself}
        >
          Cancel
        </.button>
        <.button
          type="button"
          variant="destructive"
          phx-click="confirm_delete"
          phx-target={@myself}
          disabled={@delete_modal.confirm_text != @delete_modal.name}
        >
          Delete
        </.button>
      </div>
    </div>
    """
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  @spec authorize_create(String.t(), term()) :: :ok | {:error, :forbidden}
  defp authorize_create(type, scope) do
    case Map.get(@create_actions, type) do
      nil ->
        {:error, :forbidden}

      action ->
        org = scope && scope.organization

        case Policy.authorize_and_track(action, scope, org) do
          :ok -> :ok
          {:error, _} -> {:error, :forbidden}
        end
    end
  end

  @spec do_create(String.t(), term(), String.t(), String.t() | nil, String.t()) ::
          {:ok, map()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :forbidden}
          | {:error, :limit_exceeded, map()}
  defp do_create("api", scope, project_id, _parent_id, name) do
    Apis.create_api(%{
      name: name,
      organization_id: scope.organization.id,
      project_id: project_id,
      user_id: scope.user.id
    })
  end

  defp do_create("flow", scope, project_id, _parent_id, name) do
    Flows.create_flow(%{
      name: name,
      organization_id: scope.organization.id,
      project_id: project_id,
      user_id: scope.user.id
    })
  end

  defp do_create("page", scope, project_id, parent_id, title) do
    Pages.create_page(%{
      title: title,
      organization_id: scope.organization.id,
      project_id: project_id,
      user_id: scope.user.id,
      parent_id: parent_id
    })
  end

  defp do_create("playground", scope, project_id, _parent_id, name) do
    Playgrounds.create_playground(%{
      name: name,
      organization_id: scope.organization.id,
      project_id: project_id,
      user_id: scope.user.id
    })
  end

  defp do_create(_unknown, _scope, _project_id, _parent_id, _name) do
    {:error, :forbidden}
  end

  @spec canonical_url_for_create(String.t(), term(), map() | nil, map()) :: String.t()
  defp canonical_url_for_create("api", scope, project, resource) do
    org_slug = scope.organization.slug
    project_slug = project && project.slug
    "/orgs/#{org_slug}/projects/#{project_slug}/apis/#{resource.slug}/edit"
  end

  defp canonical_url_for_create("flow", scope, project, resource) do
    org_slug = scope.organization.slug
    project_slug = project && project.slug
    "/orgs/#{org_slug}/projects/#{project_slug}/flows/#{resource.id}/edit"
  end

  defp canonical_url_for_create("page", scope, project, resource) do
    org_slug = scope.organization.slug
    project_slug = project && project.slug
    "/orgs/#{org_slug}/projects/#{project_slug}/pages/#{resource.slug}/edit"
  end

  defp canonical_url_for_create("playground", scope, project, resource) do
    org_slug = scope.organization.slug
    project_slug = project && project.slug
    "/orgs/#{org_slug}/projects/#{project_slug}/playgrounds/#{resource.slug}/edit"
  end

  @spec find_project([map()], String.t()) :: map() | nil
  defp find_project(projects, project_id) do
    case Enum.find(projects, fn %{project: p} -> p.id == project_id end) do
      nil -> nil
      %{project: p} -> p
    end
  end

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  @spec modal_title(map() | nil) :: String.t()
  defp modal_title(nil), do: ""

  defp modal_title(%{type: type}) do
    case type do
      "api" -> "APIs"
      "flow" -> "Flows"
      "page" -> "Pages"
      "playground" -> "Playgrounds"
      other -> String.capitalize(other)
    end
  end

  @spec form_field_label(String.t()) :: String.t()
  defp form_field_label("page"), do: "Title"
  defp form_field_label(_), do: "Name"

  @spec form_field_placeholder(String.t()) :: String.t()
  defp form_field_placeholder("api"), do: "My API"
  defp form_field_placeholder("flow"), do: "My Flow"
  defp form_field_placeholder("page"), do: "Page Title"
  defp form_field_placeholder("playground"), do: "My Playground"
  defp form_field_placeholder(_), do: "Name"

  defp load_projects(nil), do: []
  defp load_projects(%{organization: nil}), do: []

  defp load_projects(%{organization: org}) do
    Projects.list_projects_with_counts(org)
  end

  defp load_expanded_prefs(nil), do: []
  defp load_expanded_prefs(%{user: nil}), do: []

  defp load_expanded_prefs(%{user: user}) do
    Accounts.get_user_preference(user, ["sidebar_tree", "expanded"], [])
  end

  defp auto_expand_from_path(nil, _projects), do: []
  defp auto_expand_from_path("", _projects), do: []

  defp auto_expand_from_path(path, projects) do
    case Regex.run(
           ~r{/orgs/[^/]+/projects/([^/]+)(?:/(apis|flows|pages|playgrounds))?},
           path
         ) do
      [_, project_slug, group] when is_binary(group) and group != "" ->
        expand_keys_for_slug(projects, project_slug, group)

      [_, project_slug] ->
        expand_keys_for_slug(projects, project_slug, nil)

      _ ->
        []
    end
  end

  defp expand_keys_for_slug(projects, project_slug, group) do
    case Enum.find(projects, fn %{project: p} -> p.slug == project_slug end) do
      nil -> []
      %{project: p} when is_binary(group) -> ["project:#{p.id}", "#{group}:#{p.id}"]
      %{project: p} -> ["project:#{p.id}"]
    end
  end

  defp load_children(cache, "project", _id), do: cache

  defp load_children(cache, "pages", project_id) do
    Map.put_new_lazy(cache, "pages:#{project_id}", fn ->
      Pages.list_page_tree(project_id)
    end)
  end

  defp load_children(cache, "apis", project_id) do
    Map.put_new_lazy(cache, "apis:#{project_id}", fn ->
      Apis.list_for_project(project_id)
    end)
  end

  defp load_children(cache, "flows", project_id) do
    Map.put_new_lazy(cache, "flows:#{project_id}", fn ->
      Flows.list_for_project(project_id)
    end)
  end

  defp load_children(cache, "playgrounds", project_id) do
    Map.put_new_lazy(cache, "playgrounds:#{project_id}", fn ->
      Playgrounds.list_for_project(project_id)
    end)
  end

  defp load_children(cache, _, _), do: cache

  # Pre-populate children for every group key present in `expanded` so auto-expanded
  # groups (from URL) render their items instead of showing "No items".
  @spec preload_expanded_children(map(), [String.t()]) :: map()
  defp preload_expanded_children(cache, expanded) do
    Enum.reduce(expanded, cache, fn key, acc ->
      case String.split(key, ":", parts: 2) do
        [type, id] -> load_children(acc, type, id)
        _ -> acc
      end
    end)
  end

  defp persist_expanded_async(nil, _), do: :ok
  defp persist_expanded_async(%{user: nil}, _), do: :ok

  defp persist_expanded_async(%{user: user}, expanded) do
    Task.Supervisor.start_child(Blackboex.TaskSupervisor, fn ->
      _ = Accounts.update_user_preference(user, ["sidebar_tree", "expanded"], expanded)
    end)

    :ok
  end

  defp canonical_url(type, scope, project, item) do
    org_slug = scope && scope.organization && scope.organization.slug
    "/orgs/#{org_slug}/projects/#{project.slug}/#{type}/#{item_slug(type, item)}"
  end

  defp item_slug("pages", item), do: "#{item.slug}/edit"
  defp item_slug("playgrounds", item), do: "#{item.slug}/edit"
  defp item_slug("flows", item), do: "#{item.id}/edit"
  defp item_slug(_type, item), do: item.slug

  defp item_label("pages", item), do: item.title
  defp item_label(_type, item), do: item.name

  defp type_icon("pages"), do: "hero-document-text-2xs"
  defp type_icon("apis"), do: "hero-bolt-micro"
  defp type_icon("flows"), do: "hero-arrow-path-micro"
  defp type_icon("playgrounds"), do: "hero-code-bracket-micro"
  defp type_icon(_), do: "hero-square-2-stack-micro"

  defp type_color("pages"), do: "text-accent-sky"
  defp type_color("apis"), do: "text-accent-amber"
  defp type_color("flows"), do: "text-accent-violet"
  defp type_color("playgrounds"), do: "text-accent-emerald"
  defp type_color(_), do: "text-muted-foreground"

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :url, :string, required: true
  attr :current_path, :string, required: true

  defp project_action_link(assigns) do
    assigns = assign(assigns, :is_active, active_path?(assigns.current_path, assigns.url))

    ~H"""
    <.link
      navigate={@url}
      class={[
        "flex items-center gap-1.5 rounded px-2 py-0.5 text-xs truncate",
        if(@is_active,
          do: "bg-accent text-accent-foreground font-medium",
          else: "text-muted-foreground hover:bg-muted hover:text-foreground"
        )
      ]}
      aria-current={if @is_active, do: "page", else: nil}
    >
      <.icon name={@icon} class="size-3 shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  defp project_action_url(scope, project, action) do
    "/orgs/#{scope.organization.slug}/projects/#{project.slug}/#{action}"
  end

  defp active_path?(nil, _url), do: false
  defp active_path?(current_path, url), do: String.starts_with?(current_path, url)

  # Returns the singular resource type string for a given group type string or singular string.
  @spec singular_type(String.t()) :: String.t()
  defp singular_type(type), do: Map.get(@singular, type, type)

  # Looks up an item from tree_children cache by singular type + id.
  @spec find_item_in_cache(map(), String.t(), String.t()) :: map() | nil
  defp find_item_in_cache(tree_children, type, id) do
    plural = Map.get(@plural, type, "#{type}s")
    Enum.find_value(tree_children, &find_in_group(&1, plural, id))
  end

  @spec find_in_group({String.t(), list()}, String.t(), String.t()) :: map() | nil
  defp find_in_group({key, items}, plural, id) do
    if String.starts_with?(key, "#{plural}:") do
      find_item_in_group_items(plural, items, id)
    end
  end

  @spec find_item_in_group_items(String.t(), list(), String.t()) :: map() | nil
  defp find_item_in_group_items("pages", items, id), do: find_page_in_tree(items, id)

  defp find_item_in_group_items(_plural, items, id) do
    Enum.find(items, fn item -> item.id == id end)
  end

  @spec find_page_in_tree(list(), String.t()) :: map() | nil
  defp find_page_in_tree(nodes, id) do
    Enum.find_value(nodes, fn
      %{page: page, children: children} ->
        if page.id == id, do: page, else: find_page_in_tree(children || [], id)

      %{id: page_id} = page ->
        if page_id == id, do: page

      _ ->
        nil
    end)
  end

  @spec do_confirmed_delete(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_confirmed_delete(socket, type, id) do
    scope = socket.assigns.current_scope

    with :ok <- authorize_delete(type, scope),
         {:ok, item} <- fetch_owned_item(type, scope, id),
         {:ok, _} <- do_delete(type, item) do
      socket =
        socket
        |> assign(:delete_modal, nil)
        |> refresh_children(type, item)

      if maybe_redirect_after_delete?(socket.assigns.current_path, item) do
        {:noreply, push_navigate(socket, to: project_overview_url(scope))}
      else
        {:noreply, socket}
      end
    else
      {:error, :forbidden} -> {:noreply, assign(socket, :delete_modal, nil)}
      {:error, _} -> {:noreply, socket}
    end
  end

  @spec do_submit_rename(Phoenix.LiveView.Socket.t(), String.t(), String.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_submit_rename(socket, type, id, new_name) do
    scope = socket.assigns.current_scope

    with :ok <- authorize_update(type, scope),
         {:ok, item} <- fetch_owned_item(type, scope, id),
         {:ok, _updated} <- do_update(type, item, new_name) do
      {:noreply,
       socket
       |> assign(renaming: nil, rename_error: nil)
       |> refresh_children(type, item)}
    else
      {:error, :forbidden} ->
        {:noreply, assign(socket, renaming: nil, rename_error: nil)}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :rename_error, format_changeset_errors(cs))}
    end
  end

  # Returns the display name for an item based on type.
  @spec display_name(String.t(), map()) :: String.t()
  defp display_name("page", item), do: item.title
  defp display_name(_type, item), do: item.name

  @spec authorize_update(String.t(), term()) :: :ok | {:error, :forbidden}
  defp authorize_update(type, scope) do
    case Map.get(@update_actions, type) do
      nil ->
        {:error, :forbidden}

      action ->
        org = scope && scope.organization

        case Policy.authorize_and_track(action, scope, org) do
          :ok -> :ok
          {:error, _} -> {:error, :forbidden}
        end
    end
  end

  @spec authorize_delete(String.t(), term()) :: :ok | {:error, :forbidden}
  defp authorize_delete(type, scope) do
    case Map.get(@delete_actions, type) do
      nil ->
        {:error, :forbidden}

      action ->
        org = scope && scope.organization

        case Policy.authorize_and_track(action, scope, org) do
          :ok -> :ok
          {:error, _} -> {:error, :forbidden}
        end
    end
  end

  # Fetches an item from the DB and verifies ownership via org scope.
  # Uses facade functions — no direct Repo/Ecto.Query in component.
  @spec fetch_owned_item(String.t(), term(), String.t()) ::
          {:ok, map()} | {:error, :forbidden}
  defp fetch_owned_item("api", scope, id),
    do: nil_to_forbidden(Apis.get_for_org(scope.organization.id, id))

  defp fetch_owned_item("flow", scope, id),
    do: nil_to_forbidden(Flows.get_for_org(scope.organization.id, id))

  defp fetch_owned_item("page", scope, id),
    do: nil_to_forbidden(Pages.get_for_org(scope.organization.id, id))

  defp fetch_owned_item("playground", scope, id),
    do: nil_to_forbidden(Playgrounds.get_for_org(scope.organization.id, id))

  defp fetch_owned_item(_type, _scope, _id), do: {:error, :forbidden}

  @spec nil_to_forbidden(map() | nil) :: {:ok, map()} | {:error, :forbidden}
  defp nil_to_forbidden(nil), do: {:error, :forbidden}
  defp nil_to_forbidden(resource), do: {:ok, resource}

  @spec do_update(String.t(), map(), String.t()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()}
  defp do_update("api", item, name), do: Apis.update_api(item, %{name: name})
  defp do_update("flow", item, name), do: Flows.update_flow(item, %{name: name})
  defp do_update("page", item, title), do: Pages.update_page(item, %{title: title})
  defp do_update("playground", item, name), do: Playgrounds.update_playground(item, %{name: name})
  defp do_update(_type, _item, _name), do: {:error, :forbidden}

  @spec do_delete(String.t(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  defp do_delete("api", item), do: Apis.delete_api(item)
  defp do_delete("flow", item), do: Flows.delete_flow(item)
  defp do_delete("page", item), do: Pages.delete_page(item)
  defp do_delete("playground", item), do: Playgrounds.delete_playground(item)
  defp do_delete(_type, _item), do: {:error, :forbidden}

  # Refreshes the children for the group that contains the mutated item.
  @spec refresh_children(Phoenix.LiveView.Socket.t(), String.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  defp refresh_children(socket, type, item) do
    plural = Map.get(@plural, type, "#{type}s")
    project_id = item.project_id
    key = "#{plural}:#{project_id}"

    new_children =
      case type do
        "api" -> Apis.list_for_project(project_id)
        "flow" -> Flows.list_for_project(project_id)
        "page" -> Pages.list_page_tree(project_id)
        "playground" -> Playgrounds.list_for_project(project_id)
        _ -> Map.get(socket.assigns.tree_children, key, [])
      end

    assign(socket, :tree_children, Map.put(socket.assigns.tree_children, key, new_children))
  end

  # Returns true if the deleted item's id appears in the current path
  # (meaning the user is currently viewing it).
  @spec maybe_redirect_after_delete?(String.t() | nil, map()) :: boolean()
  defp maybe_redirect_after_delete?(nil, _item), do: false

  defp maybe_redirect_after_delete?(current_path, item) do
    String.contains?(current_path, item.id) or
      (Map.has_key?(item, :slug) and item.slug != nil and
         String.contains?(current_path, item.slug))
  end

  # Returns the project overview URL for the current scope.
  @spec project_overview_url(term()) :: String.t()
  defp project_overview_url(scope) do
    "/orgs/#{scope.organization.slug}"
  end

  # ── move_node helpers ──────────────────────────────────────────────────────

  # Valid (node_type, parent_type) combinations for DnD moves.
  # Using a compile-time list avoids String.to_atom on user input.
  @valid_move_combos [
    {"page", "pages"},
    {"page", "page"},
    {"api", "apis"},
    {"flow", "flows"},
    {"playground", "playgrounds"}
  ]

  @spec parse_move(map()) :: {:ok, map()} | {:error, atom()}
  defp parse_move(
         %{
           "node_id" => node_id,
           "node_type" => nt,
           "new_parent_type" => npt,
           "new_parent_id" => npi
         } = params
       )
       when is_binary(node_id) and is_binary(nt) and is_binary(npt) and is_binary(npi) do
    if {nt, npt} in @valid_move_combos do
      {:ok,
       %{
         node_id: node_id,
         node_type: nt,
         parent_type: npt,
         parent_id: npi,
         index: Map.get(params, "new_index")
       }}
    else
      {:error, :invalid_target_type}
    end
  end

  defp parse_move(_), do: {:error, :invalid_params}

  @spec authorize_move(map(), term()) :: {:ok, map()} | {:error, atom()}
  defp authorize_move(
         %{node_type: nt, node_id: node_id, parent_type: pt, parent_id: parent_id},
         scope
       ) do
    with {:ok, resource} <- fetch_owned_item(nt, scope, node_id),
         :ok <- check_destination_scope(nt, pt, parent_id, resource, scope),
         :ok <- authorize_update_policy(nt, scope) do
      {:ok, resource}
    end
  end

  @spec check_destination_scope(String.t(), String.t(), String.t(), map(), term()) ::
          :ok | {:error, atom()}
  defp check_destination_scope("page", pt, parent_id, resource, _scope) do
    if destination_in_same_project?(pt, parent_id, resource),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp check_destination_scope(nt, _pt, parent_id, _resource, scope)
       when nt in ["api", "flow", "playground"] do
    if destination_in_same_org?(parent_id, scope),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp check_destination_scope(_nt, _pt, _parent_id, _resource, _scope),
    do: {:error, :forbidden}

  @spec authorize_update_policy(String.t(), term()) :: :ok | {:error, atom()}
  defp authorize_update_policy(nt, scope) do
    case Map.get(@update_actions, nt) do
      nil ->
        {:error, :forbidden}

      action ->
        case Policy.authorize_and_track(action, scope, scope.organization) do
          :ok -> :ok
          {:error, _} -> {:error, :forbidden}
        end
    end
  end

  # Checks whether the destination project is in the current scope's org.
  @spec destination_in_same_org?(String.t(), term()) :: boolean()
  defp destination_in_same_org?(destination_project_id, scope) do
    org_id = scope && scope.organization && scope.organization.id

    if org_id do
      Projects.get_project(org_id, destination_project_id) != nil
    else
      false
    end
  end

  # Checks whether the destination (for a page move) is in the same project as the resource.
  # pt is "pages" (group, meaning root of same project) or "page" (new parent page).
  @spec destination_in_same_project?(String.t(), String.t(), map()) :: boolean()
  defp destination_in_same_project?("pages", parent_id, resource) do
    # parent_id here is the project_id (from data-parent-id on the pages group list)
    parent_id == resource.project_id
  end

  defp destination_in_same_project?("page", parent_page_id, resource) do
    # Look up the target parent page (org-scoped) and compare project_ids
    case Pages.get_for_org(resource.organization_id, parent_page_id) do
      nil -> false
      parent_page -> parent_page.project_id == resource.project_id
    end
  end

  defp destination_in_same_project?(_pt, _parent_id, _resource), do: false

  @spec apply_move(map(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  defp apply_move(%{node_type: "page", parent_type: pt, parent_id: parent_id, index: idx}, page) do
    # "pages" group means move to root (nil parent) within same project
    new_parent = if pt == "page", do: parent_id, else: nil
    Pages.move_page(page, new_parent, idx || 0)
  end

  defp apply_move(%{node_type: "api", parent_id: new_project_id}, api),
    do: Apis.move_api(api, new_project_id)

  defp apply_move(%{node_type: "flow", parent_id: new_project_id}, flow),
    do: Flows.move_flow(flow, new_project_id)

  defp apply_move(%{node_type: "playground", parent_id: new_project_id}, playground),
    do: Playgrounds.move_playground(playground, new_project_id)

  # Refreshes the tree children for both the source and destination groups
  # after a successful move. Receives the updated resource and the pre-move project_id
  # directly — no second DB fetch.
  @spec refresh_tree_after_move(Phoenix.LiveView.Socket.t(), map(), map(), String.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp refresh_tree_after_move(socket, %{node_type: "page"}, updated_page, _old_project_id) do
    key = "pages:#{updated_page.project_id}"
    new_list = Pages.list_page_tree(updated_page.project_id)
    assign(socket, :tree_children, Map.put(socket.assigns.tree_children, key, new_list))
  end

  defp refresh_tree_after_move(
         socket,
         %{node_type: nt, parent_id: new_project_id},
         _updated,
         old_project_id
       )
       when nt in ["api", "flow", "playground"] do
    plural = Map.get(@plural, nt, "#{nt}s")
    dest_key = "#{plural}:#{new_project_id}"

    new_list = list_for_move(nt, new_project_id)
    tree = Map.put(socket.assigns.tree_children, dest_key, new_list)

    # Also refresh source group if project changed
    tree =
      if old_project_id && old_project_id != new_project_id do
        src_key = "#{plural}:#{old_project_id}"
        src_list = list_for_move(nt, old_project_id)
        Map.put(tree, src_key, src_list)
      else
        tree
      end

    assign(socket, :tree_children, tree)
  end

  defp refresh_tree_after_move(socket, _rules, _updated, _old_project_id), do: socket

  @spec list_for_move(String.t(), String.t()) :: [map()]
  defp list_for_move("api", project_id), do: Apis.list_for_project(project_id)
  defp list_for_move("flow", project_id), do: Flows.list_for_project(project_id)
  defp list_for_move("playground", project_id), do: Playgrounds.list_for_project(project_id)
  defp list_for_move(_, _), do: []

  @spec humanize_move_error(atom()) :: String.t()
  defp humanize_move_error(:forbidden), do: "Move not allowed."
  defp humanize_move_error(:invalid_target_type), do: "Cannot move to that location."
  defp humanize_move_error(:invalid_params), do: "Invalid move request."
  defp humanize_move_error(:self_parent), do: "A page cannot be its own parent."

  defp humanize_move_error(:circular_reference),
    do: "Cannot move a page under one of its own descendants."

  defp humanize_move_error(:max_depth_exceeded), do: "Maximum page depth exceeded."
  defp humanize_move_error(_), do: "Move failed."
end
