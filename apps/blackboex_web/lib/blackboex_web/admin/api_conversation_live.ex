defmodule BlackboexWeb.Admin.ApiConversationLive do
  @moduledoc """
  Backpex LiveResource for viewing API conversations in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Apis.ApiConversation,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Apis.ApiConversation.admin_changeset/3,
      create_changeset: &Blackboex.Apis.ApiConversation.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "API Conversation"

  @impl Backpex.LiveResource
  def plural_name, do: "API Conversations"

  @impl Backpex.LiveResource
  def fields do
    [
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
        readonly: true
      },
      messages: %{
        module: Backpex.Fields.Textarea,
        label: "Messages",
        readonly: true,
        only: [:show]
      },
      metadata: %{
        module: Backpex.Fields.Textarea,
        label: "Metadata",
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
