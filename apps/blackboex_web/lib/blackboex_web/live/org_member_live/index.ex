defmodule BlackboexWeb.OrgMemberLive.Index do
  @moduledoc """
  Organization member management.
  Lists members with roles; owners can edit roles and remove members.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.UI.InlineSelect
  import BlackboexWeb.OrgSettingsLive, only: [org_settings_tabs: 1]

  alias Blackboex.Organizations

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    current_user = socket.assigns.current_scope.user
    members = if org, do: Organizations.list_memberships(org), else: []

    current_membership =
      if org, do: Organizations.get_user_membership(org, current_user), else: nil

    is_owner = current_membership != nil and current_membership.role == :owner

    {:ok,
     socket
     |> assign(:page_title, "Members")
     |> assign(:org, org)
     |> assign(:members, members)
     |> assign(:is_owner, is_owner)}
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.members, &(&1.id == id)) do
      nil -> {:noreply, put_flash(socket, :error, "Member not found")}
      membership -> do_remove_member(socket, membership)
    end
  end

  @impl true
  def handle_event("update_role", %{"membership_id" => id, "role" => role}, socket) do
    case Enum.find(socket.assigns.members, &(&1.id == id)) do
      nil -> {:noreply, socket}
      membership -> do_update_role(socket, membership, role)
    end
  end

  defp do_remove_member(socket, membership) do
    case Organizations.remove_member(socket.assigns.org, membership) do
      {:ok, _} ->
        members = Enum.reject(socket.assigns.members, &(&1.id == membership.id))
        {:noreply, assign(socket, members: members)}

      {:error, :last_owner} ->
        {:noreply, put_flash(socket, :error, "Cannot remove the last owner of this organization")}
    end
  end

  defp do_update_role(socket, membership, role) do
    role_atom = String.to_existing_atom(role)

    case Organizations.update_member_role(membership, role_atom) do
      {:ok, updated} -> apply_role_update(socket, membership.id, updated.role)
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Failed to update role")}
    end
  end

  defp apply_role_update(socket, membership_id, new_role) do
    members =
      Enum.map(socket.assigns.members, fn m ->
        if m.id == membership_id, do: %{m | role: new_role}, else: m
      end)

    {:noreply, assign(socket, :members, members)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.header>
        <span class="flex items-center gap-2">
          <.icon name="hero-user-group" class="size-5 text-accent-blue" /> Members
        </span>
        <:subtitle>Manage organization members and roles</:subtitle>
      </.header>

      <.org_settings_tabs current_scope={@current_scope} active="members" />

      <%= if @members == [] do %>
        <.empty_state
          icon="hero-user-group"
          title="No members yet"
          description="This organization has no members."
        />
      <% else %>
        <.table id="members" rows={@members}>
          <:col :let={m} label="Email">{m.user && m.user.email}</:col>
          <:col :let={m} label="Role">
            <%= if @is_owner do %>
              <form
                id={"role-form-#{m.id}"}
                phx-change="update_role"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="membership_id" value={m.id} />
                <.inline_select
                  name="role"
                  value={m.role}
                  options={[{"Owner", "owner"}, {"Admin", "admin"}, {"Member", "member"}]}
                  class="w-28"
                />
              </form>
            <% else %>
              <.badge variant="secondary">{m.role}</.badge>
            <% end %>
          </:col>
          <:action :let={m} :if={@is_owner}>
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
    </.page>
    """
  end
end
