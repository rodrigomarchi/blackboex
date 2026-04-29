defmodule BlackboexWeb.ProjectLive.EnvVars do
  @moduledoc """
  Project-scoped LiveView for managing generic env vars (`kind = "env"`).

  - Lists env vars for the current project, with values always masked.
  - Create form validates name format + value length.
  - Update is value-only (name is immutable to avoid breaking references in
    generated code and flows).
  - Delete requires confirmation.

  Access is enforced by the `SetProjectFromUrl` on_mount hook.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Modal
  import BlackboexWeb.Components.Shared.ProjectSettingsTabs

  alias Blackboex.ProjectEnvVars
  alias Blackboex.ProjectEnvVars.ProjectEnvVar

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    project = scope.project

    env_vars = if project, do: ProjectEnvVars.list_env_vars(project.id), else: []

    {:ok,
     socket
     |> assign(:page_title, "Env Vars")
     |> assign(:org, org)
     |> assign(:project, project)
     |> assign(:env_vars, env_vars)
     |> assign(:show_create_modal, false)
     |> assign(:edit_id, nil)
     |> assign(:delete_id, nil)
     |> assign(:create_form, to_form(%{"name" => "", "value" => ""}, as: :env_var))
     |> assign(:edit_form, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header icon="hero-variable" icon_class="text-accent-violet" title="Env Vars">
      <:actions>
        <.button variant="primary" phx-click="open_create_modal">
          <.icon name="hero-plus" class="mr-2 size-4 text-accent-emerald" /> New Env Var
        </.button>
      </:actions>
    </.page_header>
    <.page>
      <.project_settings_tabs
        :if={@project}
        active={:env_vars}
        org_slug={@org.slug}
        project_slug={@project.slug}
      />

      <%= if @env_vars == [] do %>
        <.empty_state
          icon="hero-variable"
          icon_class="text-accent-violet"
          title="No env vars yet"
          description="Create a variable to pass config to your APIs, flows or playgrounds."
        />
      <% else %>
        <.table id="env-vars" rows={@env_vars}>
          <:col :let={ev} label="Name">
            <span class="font-mono text-xs">{ev.name}</span>
          </:col>
          <:col :let={_ev} label="Value">
            <span class="font-mono text-xs text-muted-foreground" data-role="masked-value">
              ••••••••
            </span>
          </:col>
          <:col :let={ev} label="Created">
            <span class="text-xs text-muted-foreground">
              {Calendar.strftime(ev.inserted_at, "%b %d, %Y")}
            </span>
          </:col>
          <:action :let={ev}>
            <div class="flex items-center gap-2">
              <.button
                variant="ghost"
                size="compact"
                phx-click="open_edit_modal"
                phx-value-id={ev.id}
                data-role="edit-env-var"
              >
                Edit
              </.button>
              <.button
                variant="ghost"
                size="compact"
                class="link-destructive"
                phx-click="open_delete_modal"
                phx-value-id={ev.id}
                data-role="delete-env-var"
              >
                Delete
              </.button>
            </div>
          </:action>
        </.table>
      <% end %>

      <%!-- Create Modal --%>
      <.modal show={@show_create_modal} on_close="close_create_modal" title="Create Env Var">
        <.form
          :let={f}
          for={@create_form}
          phx-submit="create_env_var"
          phx-change="validate_create"
          id="create-env-var-form"
          class="space-y-4"
        >
          <.input
            field={f[:name]}
            type="text"
            label="Name"
            placeholder="MY_API_TOKEN"
            required
            maxlength="255"
          />
          <.input
            field={f[:value]}
            type="text"
            label="Value"
            required
          />
          <p class="text-xs text-muted-foreground">
            Name must contain only letters, numbers and underscores. The value is stored
            encrypted and will be masked after creation — copy it now if you need it
            elsewhere.
          </p>
          <.form_actions spacing="tight">
            <.button type="button" variant="outline" phx-click="close_create_modal">
              Cancel
            </.button>
            <.button type="submit" variant="primary">
              <.icon name="hero-check" class="mr-1.5 size-3.5 text-accent-emerald" /> Create
            </.button>
          </.form_actions>
        </.form>
      </.modal>

      <%!-- Edit Modal --%>
      <.modal
        :if={@edit_id && @edit_form}
        show={true}
        on_close="close_edit_modal"
        title="Edit Env Var"
      >
        <.form
          :let={f}
          for={@edit_form}
          phx-submit="update_env_var"
          phx-change="validate_update"
          id={"edit-env-var-form-#{@edit_id}"}
          class="space-y-4"
        >
          <input type="hidden" name="_id" value={@edit_id} />
          <.input field={f[:name]} type="text" label="Name" disabled />
          <.input field={f[:value]} type="text" label="New value" required />
          <p class="text-xs text-muted-foreground">
            Name is immutable. Only the value can be updated.
          </p>
          <.form_actions spacing="tight">
            <.button type="button" variant="outline" phx-click="close_edit_modal">
              Cancel
            </.button>
            <.button type="submit" variant="primary">
              <.icon name="hero-check" class="mr-1.5 size-3.5 text-accent-emerald" /> Save
            </.button>
          </.form_actions>
        </.form>
      </.modal>

      <%!-- Delete Modal --%>
      <.modal
        :if={@delete_id}
        show={true}
        on_close="close_delete_modal"
        title="Delete Env Var"
      >
        <div class="space-y-4">
          <p class="text-sm">
            This will permanently remove the env var. Running APIs, Flows or Playgrounds
            that reference it will no longer receive a value.
          </p>
          <.form_actions spacing="tight">
            <.button type="button" variant="outline" phx-click="close_delete_modal">
              Cancel
            </.button>
            <.button
              type="button"
              variant="destructive"
              phx-click="confirm_delete_env_var"
              phx-value-id={@delete_id}
              data-role="confirm-delete-env-var"
            >
              <.icon name="hero-trash" class="mr-1.5 size-3.5" /> Delete
            </.button>
          </.form_actions>
        </div>
      </.modal>
    </.page>
    """
  end

  # ── Create ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:create_form, to_form(%{"name" => "", "value" => ""}, as: :env_var))}
  end

  @impl true
  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  @impl true
  def handle_event("validate_create", %{"env_var" => params}, socket) do
    changeset =
      %ProjectEnvVar{}
      |> ProjectEnvVar.changeset(Map.merge(params, scope_attrs(socket)))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :create_form, to_form(changeset, as: :env_var))}
  end

  @impl true
  def handle_event("create_env_var", %{"env_var" => params}, socket) do
    attrs = Map.merge(params, scope_attrs(socket))

    case ProjectEnvVars.create(attrs) do
      {:ok, _env_var} ->
        project = socket.assigns.project
        env_vars = ProjectEnvVars.list_env_vars(project.id)

        {:noreply,
         socket
         |> assign(:env_vars, env_vars)
         |> assign(:show_create_modal, false)
         |> assign(:create_form, to_form(%{"name" => "", "value" => ""}, as: :env_var))
         |> put_flash(:info, "Env var created")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:create_form, to_form(changeset, as: :env_var))
         |> put_flash(:error, "Please fix the errors below.")}
    end
  end

  # ── Edit ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    project = socket.assigns.project

    case Enum.find(socket.assigns.env_vars, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Env var not found")}

      env_var when env_var.project_id != project.id ->
        {:noreply, put_flash(socket, :error, "Env var not found")}

      env_var ->
        form_data = %{"name" => env_var.name, "value" => ""}

        {:noreply,
         socket
         |> assign(:edit_id, env_var.id)
         |> assign(:edit_form, to_form(form_data, as: :env_var))}
    end
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, edit_id: nil, edit_form: nil)}
  end

  @impl true
  def handle_event("validate_update", %{"env_var" => params}, socket) do
    case find_env_var(socket, socket.assigns.edit_id) do
      nil ->
        {:noreply,
         socket
         |> assign(edit_id: nil, edit_form: nil)
         |> put_flash(:error, "Env var no longer exists")}

      env_var ->
        changeset =
          env_var
          |> ProjectEnvVar.changeset(Map.take(params, ["value"]))
          |> Map.put(:action, :validate)

        form = to_form(changeset, as: :env_var)
        # Keep the name visible (changeset cast drops it since it didn't change)
        {:noreply, assign(socket, :edit_form, form)}
    end
  end

  @impl true
  def handle_event("update_env_var", %{"env_var" => params, "_id" => id}, socket) do
    project = socket.assigns.project

    case find_env_var(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Env var not found")}

      env_var when env_var.project_id != project.id ->
        {:noreply, put_flash(socket, :error, "Env var not found")}

      env_var ->
        case ProjectEnvVars.update(env_var, Map.take(params, ["value"])) do
          {:ok, _updated} ->
            env_vars = ProjectEnvVars.list_env_vars(project.id)

            {:noreply,
             socket
             |> assign(:env_vars, env_vars)
             |> assign(:edit_id, nil)
             |> assign(:edit_form, nil)
             |> put_flash(:info, "Env var updated")}

          {:error, changeset} ->
            {:noreply, assign(socket, :edit_form, to_form(changeset, as: :env_var))}
        end
    end
  end

  # ── Delete ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_delete_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_id, id)}
  end

  @impl true
  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, :delete_id, nil)}
  end

  @impl true
  def handle_event("confirm_delete_env_var", %{"id" => id}, socket) do
    project = socket.assigns.project

    case find_env_var(socket, id) do
      nil ->
        {:noreply,
         socket
         |> assign(:delete_id, nil)
         |> put_flash(:error, "Env var not found")}

      env_var when env_var.project_id != project.id ->
        {:noreply,
         socket
         |> assign(:delete_id, nil)
         |> put_flash(:error, "Env var not found")}

      env_var ->
        case ProjectEnvVars.delete(env_var) do
          {:ok, _} ->
            env_vars = ProjectEnvVars.list_env_vars(project.id)

            {:noreply,
             socket
             |> assign(:env_vars, env_vars)
             |> assign(:delete_id, nil)
             |> put_flash(:info, "Env var deleted")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:delete_id, nil)
             |> put_flash(:error, "Failed to delete env var")}
        end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp scope_attrs(socket) do
    scope = socket.assigns.current_scope

    %{
      "project_id" => scope.project.id,
      "organization_id" => scope.organization.id,
      "kind" => "env"
    }
  end

  defp find_env_var(socket, id), do: Enum.find(socket.assigns.env_vars, &(&1.id == id))
end
