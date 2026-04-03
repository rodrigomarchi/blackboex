defmodule BlackboexWeb.Admin.DataStoreEntryLive do
  @moduledoc """
  Backpex LiveResource for managing data store entries in the admin panel.
  Editable with caution.
  """

  alias Blackboex.Apis.DataStore.Entry

  use Backpex.LiveResource,
    adapter_config: [
      schema: Entry,
      repo: Blackboex.Repo,
      update_changeset: &Entry.admin_changeset/3,
      create_changeset: &Entry.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Data Store Entry"

  @impl Backpex.LiveResource
  def plural_name, do: "Data Store Entries"

  @impl Backpex.LiveResource
  def fields do
    [
      key: %{
        module: Backpex.Fields.Text,
        label: "Key",
        searchable: true
      },
      value: %{
        module: Backpex.Fields.Text,
        label: "Value",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :value)

          text =
            if is_map(value) or is_list(value),
              do: inspect(value, pretty: true, limit: :infinity),
              else: to_string(value || "")

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <pre class="text-xs whitespace-pre-wrap max-h-96 overflow-auto"><%= @text %></pre>
          """
        end
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
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
