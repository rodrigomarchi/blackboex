defmodule BlackboexWeb.Admin.MembershipLive do
  @moduledoc """
  Backpex LiveResource for managing organization memberships in the admin panel.
  Edit limited to role changes only.
  """

  alias Blackboex.Organizations.Membership

  use Backpex.LiveResource,
    adapter_config: [
      schema: Membership,
      repo: Blackboex.Repo,
      update_changeset: &Membership.admin_changeset/3,
      create_changeset: &Membership.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Membership"

  @impl Backpex.LiveResource
  def plural_name, do: "Memberships"

  @impl Backpex.LiveResource
  def fields do
    [
      role: %{
        module: Backpex.Fields.Select,
        label: "Role",
        options: [Owner: :owner, Admin: :admin, Member: :member]
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
