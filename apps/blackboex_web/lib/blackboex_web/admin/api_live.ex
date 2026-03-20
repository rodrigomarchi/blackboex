defmodule BlackboexWeb.Admin.ApiLive do
  @moduledoc """
  Backpex LiveResource for managing APIs in the admin panel.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Apis.Api,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Apis.Api.admin_changeset/3,
      create_changeset: &Blackboex.Apis.Api.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "API"

  @impl Backpex.LiveResource
  def plural_name, do: "APIs"

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
        readonly: true
      },
      status: %{
        module: Backpex.Fields.Text,
        label: "Status"
      },
      visibility: %{
        module: Backpex.Fields.Text,
        label: "Visibility",
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
  def can?(assigns, :index, _item), do: platform_admin?(assigns)
  def can?(assigns, :show, _item), do: platform_admin?(assigns)
  def can?(assigns, :edit, _item), do: platform_admin?(assigns)
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, _action, _item), do: false

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
