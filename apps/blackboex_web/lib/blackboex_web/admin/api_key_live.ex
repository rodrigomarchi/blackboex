defmodule BlackboexWeb.Admin.ApiKeyLive do
  @moduledoc """
  Backpex LiveResource for viewing API keys in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Apis.ApiKey,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Apis.ApiKey.admin_changeset/3,
      create_changeset: &Blackboex.Apis.ApiKey.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "API Key"

  @impl Backpex.LiveResource
  def plural_name, do: "API Keys"

  @impl Backpex.LiveResource
  def fields do
    [
      key_prefix: %{
        module: Backpex.Fields.Text,
        label: "Key Prefix",
        searchable: true
      },
      label: %{
        module: Backpex.Fields.Text,
        label: "Label",
        searchable: true
      },
      rate_limit: %{
        module: Backpex.Fields.Number,
        label: "Rate Limit"
      },
      last_used_at: %{
        module: Backpex.Fields.DateTime,
        label: "Last Used"
      },
      expires_at: %{
        module: Backpex.Fields.DateTime,
        label: "Expires At"
      },
      revoked_at: %{
        module: Backpex.Fields.DateTime,
        label: "Revoked At",
        only: [:show]
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
        readonly: true,
        only: [:show]
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID",
        readonly: true,
        only: [:show]
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
  def can?(_assigns, _action, _item), do: false

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
