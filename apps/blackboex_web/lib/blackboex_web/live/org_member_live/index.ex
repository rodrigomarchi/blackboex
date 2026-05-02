defmodule BlackboexWeb.OrgMemberLive.Index do
  @moduledoc """
  Organization member management.
  Lists members with roles; owners can edit roles and remove members.
  """

  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Badge
  import BlackboexWeb.Components.Modal
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
     |> assign(:is_owner, is_owner)
     |> assign(:show_invite_modal, false)
     |> assign(:invite_form, build_invite_form(%{}))}
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

  @impl true
  def handle_event("open_invite_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_invite_modal, true)
     |> assign(:invite_form, build_invite_form(%{}))}
  end

  @impl true
  def handle_event("close_invite_modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  @impl true
  def handle_event("send_invite", %{"invitation" => params}, socket) do
    if socket.assigns.is_owner do
      do_send_invite(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Only owners can invite members.")}
    end
  end

  defp do_send_invite(socket, params) do
    role = parse_role(params["role"])
    inviter = socket.assigns.current_scope.user

    case Organizations.invite_member(socket.assigns.org, inviter, %{
           email: params["email"],
           role: role
         }) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent")
         |> assign(:show_invite_modal, false)
         |> assign(:invite_form, build_invite_form(%{}))}

      {:error, changeset} ->
        {:noreply, assign(socket, :invite_form, to_form(changeset, as: :invitation))}
    end
  end

  defp parse_role("admin"), do: :admin
  defp parse_role(_), do: :member

  defp build_invite_form(params) do
    types = %{email: :string, role: :string}

    {%{role: "member"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Map.put(:action, nil)
    |> to_form(as: :invitation)
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
    <.page_header icon="hero-user-group" icon_class="text-accent-blue" title="Members">
      <:actions>
        <.button :if={@is_owner} variant="primary" phx-click="open_invite_modal">
          <.icon name="hero-user-plus" class="mr-2 size-4 text-accent-emerald" /> Invite member
        </.button>
      </:actions>
    </.page_header>
    <.page>
      <.org_settings_tabs current_scope={@current_scope} active="members" />

      <.modal
        :if={@show_invite_modal}
        show={@show_invite_modal}
        on_close="close_invite_modal"
        title="Invite member"
      >
        <.form for={@invite_form} id="invite-form" phx-submit="send_invite">
          <.input field={@invite_form[:email]} type="email" label="Email" required />
          <.input
            field={@invite_form[:role]}
            type="select"
            label="Role"
            options={[{"Member", "member"}, {"Admin", "admin"}]}
          />
          <div class="flex justify-end gap-2">
            <.button type="button" variant="outline" phx-click="close_invite_modal">
              Cancel
            </.button>
            <.button type="submit">Send invitation</.button>
          </div>
        </.form>
      </.modal>

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
