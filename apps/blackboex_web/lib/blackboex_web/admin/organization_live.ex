defmodule BlackboexWeb.Admin.OrganizationLive do
  @moduledoc """
  Backpex LiveResource for managing organizations in the admin panel.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Organizations.Organization,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Organizations.Organization.admin_changeset/3,
      create_changeset: &Blackboex.Organizations.Organization.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Organization"

  @impl Backpex.LiveResource
  def plural_name, do: "Organizations"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      slug: %{
        module: Backpex.Fields.Text,
        label: "Slug",
        searchable: true,
        readonly: true
      },
      plan: %{
        module: Backpex.Fields.Select,
        label: "Plan",
        options: [Free: "free", Pro: "pro", Enterprise: "enterprise"]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, :index, _item), do: platform_admin?(assigns)
  def can?(assigns, :show, _item), do: platform_admin?(assigns)
  def can?(assigns, :edit, _item), do: platform_admin?(assigns)
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, _action, _item), do: false

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
