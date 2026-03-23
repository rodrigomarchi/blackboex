defmodule BlackboexWeb.Admin.UserLive do
  @moduledoc """
  Backpex LiveResource for managing users in the admin panel.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Accounts.User,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Accounts.User.admin_changeset/3,
      create_changeset: &Blackboex.Accounts.User.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def fields do
    [
      email: %{
        module: Backpex.Fields.Text,
        label: "Email",
        searchable: true
      },
      is_platform_admin: %{
        module: Backpex.Fields.Boolean,
        label: "Platform Admin"
      },
      confirmed_at: %{
        module: Backpex.Fields.DateTime,
        label: "Confirmed",
        only: [:index, :show]
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
