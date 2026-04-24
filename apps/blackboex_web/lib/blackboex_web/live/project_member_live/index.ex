defmodule BlackboexWeb.ProjectMemberLive.Index do
  @moduledoc """
  Project member management.
  Lists explicit project members and implicit org owners/admins.
  Project admins can add, edit roles, and remove explicit members.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.UI.SectionHeading
  import BlackboexWeb.Components.UI.InlineSelect
  import BlackboexWeb.Components.Shared.ProjectSettingsTabs

  alias Blackboex.Organizations
  alias Blackboex.Projects

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    project = scope.project
    org = scope.organization
    current_user = scope.user

    {explicit_members, implicit_members, eligible_members, is_admin} =
      if project && org do
        load_member_data(org, project, current_user)
      else
        {[], [], [], false}
      end

    {:ok,
     socket
     |> assign(:page_title, "Project Members")
     |> assign(:project, project)
     |> assign(:org, org)
     |> assign(:explicit_members, explicit_members)
     |> assign(:implicit_members, implicit_members)
     |> assign(:eligible_members, eligible_members)
     |> assign(:is_admin, is_admin)}
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.explicit_members, &(&1.id == id)) do
      nil -> {:noreply, socket}
      membership -> do_remove_member(socket, membership)
    end
  end

  @impl true
  def handle_event("update_role", %{"membership_id" => id, "role" => role}, socket) do
    case Enum.find(socket.assigns.explicit_members, &(&1.id == id)) do
      nil -> {:noreply, socket}
      membership -> do_update_role(socket, membership, role)
    end
  end

  @impl true
  def handle_event("add_member", %{"user_id" => user_id, "role" => role}, socket) do
    case Enum.find(socket.assigns.eligible_members, &(to_string(&1.user_id) == user_id)) do
      nil -> {:noreply, put_flash(socket, :error, "User not eligible")}
      eligible_membership -> do_add_member(socket, eligible_membership, role)
    end
  end

  defp do_remove_member(socket, membership) do
    case Projects.remove_project_member(membership) do
      {:ok, _} ->
        {:noreply, reload_members(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove member")}
    end
  end

  defp do_update_role(socket, membership, role) do
    role_atom = String.to_existing_atom(role)

    case Projects.update_project_member_role(membership, role_atom) do
      {:ok, updated} -> apply_role_update(socket, membership.id, updated.role)
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update role")}
    end
  end

  defp apply_role_update(socket, membership_id, new_role) do
    members =
      Enum.map(socket.assigns.explicit_members, fn m ->
        if m.id == membership_id, do: %{m | role: new_role}, else: m
      end)

    {:noreply, assign(socket, :explicit_members, members)}
  end

  defp do_add_member(socket, eligible_membership, role) do
    role_atom = String.to_existing_atom(role)
    user = eligible_membership.user

    case Projects.add_project_member(socket.assigns.project, user, role_atom) do
      {:ok, _} ->
        {:noreply, reload_members(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add member")}
    end
  end

  defp load_member_data(org, project, current_user) do
    explicit = Projects.list_project_members(project.id)
    explicit_user_ids = MapSet.new(explicit, & &1.user_id)

    implicit =
      org
      |> Organizations.list_memberships()
      |> Enum.filter(fn m ->
        m.role in [:owner, :admin] and m.user_id not in explicit_user_ids
      end)

    eligible = Projects.list_eligible_members(org, project)

    current_pm = Enum.find(explicit, &(&1.user_id == current_user.id))
    org_mem = Organizations.get_user_membership(org, current_user)

    is_admin =
      (current_pm != nil and current_pm.role == :admin) or
        (org_mem != nil and org_mem.role in [:owner, :admin])

    {explicit, implicit, eligible, is_admin}
  end

  defp reload_members(socket) do
    org = socket.assigns.org
    project = socket.assigns.project
    current_user = socket.assigns.current_scope.user
    {explicit, implicit, eligible, is_admin} = load_member_data(org, project, current_user)

    assign(socket,
      explicit_members: explicit,
      implicit_members: implicit,
      eligible_members: eligible,
      is_admin: is_admin
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-user-group" class="size-5 text-accent-blue" /> Project Members
        </span>
        <:subtitle>Manage access to this project</:subtitle>
      </.header>

      <.project_settings_tabs
        :if={@project && @org}
        active={:members}
        org_slug={@org.slug}
        project_slug={@project.slug}
      />

      <%!-- Direct members --%>
      <div class="space-y-3">
        <.section_heading icon="hero-users">Direct Members</.section_heading>

        <%= if @explicit_members == [] do %>
          <.empty_state
            icon="hero-user-group"
            title="No direct members"
            description="Add organization members to this project."
          />
        <% else %>
          <.table id="explicit-members" rows={@explicit_members}>
            <:col :let={m} label="Email">{m.user && m.user.email}</:col>
            <:col :let={m} label="Role">
              <%= if @is_admin do %>
                <form
                  id={"role-form-#{m.id}"}
                  phx-change="update_role"
                  class="flex items-center gap-2"
                >
                  <input type="hidden" name="membership_id" value={m.id} />
                  <.inline_select
                    name="role"
                    value={m.role}
                    options={[{"Admin", "admin"}, {"Editor", "editor"}, {"Viewer", "viewer"}]}
                    class="w-28"
                  />
                </form>
              <% else %>
                <.badge variant="secondary">{m.role}</.badge>
              <% end %>
            </:col>
            <:action :let={m} :if={@is_admin}>
              <.button
                variant="ghost"
                size="compact"
                class="link-destructive"
                phx-click="remove_member"
                phx-value-id={m.id}
                data-confirm="Remove this member?"
              >
                Remove
              </.button>
            </:action>
          </.table>
        <% end %>
      </div>

      <%!-- Implicit members (org owners/admins) --%>
      <div :if={@implicit_members != []} class="space-y-3">
        <.section_heading icon="hero-building-office">
          Implicit Access
          <:description>Organization owners and admins have automatic access</:description>
        </.section_heading>

        <.table id="implicit-members" rows={@implicit_members}>
          <:col :let={m} label="Email">{m.user && m.user.email}</:col>
          <:col :let={m} label="Access">
            <.badge variant="outline">implicit · org {m.role}</.badge>
          </:col>
        </.table>
      </div>

      <%!-- Add member form --%>
      <div :if={@is_admin and @eligible_members != []} class="space-y-3">
        <.section_heading icon="hero-user-plus">Add Member</.section_heading>

        <.form :let={_f} for={%{}} as={:member} phx-submit="add_member" id="add-member-form">
          <div class="flex items-end gap-3">
            <.input
              type="select"
              name="user_id"
              label="User"
              value={nil}
              options={Enum.map(@eligible_members, &{&1.user && &1.user.email, &1.user_id})}
            />
            <.input
              type="select"
              name="role"
              label="Role"
              value="editor"
              options={[{"Admin", "admin"}, {"Editor", "editor"}, {"Viewer", "viewer"}]}
            />
            <.button type="submit" variant="primary" class="mb-0.5">Add</.button>
          </div>
        </.form>
      </div>
    </.page>
    """
  end
end
