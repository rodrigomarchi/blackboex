defmodule BlackboexWeb.Admin.TestRequestLive do
  @moduledoc """
  Backpex LiveResource for viewing test requests in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Testing.TestRequest,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Testing.TestRequest.admin_changeset/3,
      create_changeset: &Blackboex.Testing.TestRequest.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Test Request"

  @impl Backpex.LiveResource
  def plural_name, do: "Test Requests"

  @impl Backpex.LiveResource
  def fields do
    [
      method: %{
        module: Backpex.Fields.Text,
        label: "Method",
        searchable: true
      },
      path: %{
        module: Backpex.Fields.Text,
        label: "Path",
        searchable: true
      },
      response_status: %{
        module: Backpex.Fields.Number,
        label: "Status"
      },
      duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)"
      },
      headers: %{
        module: Backpex.Fields.Textarea,
        label: "Request Headers",
        readonly: true,
        only: [:show]
      },
      body: %{
        module: Backpex.Fields.Textarea,
        label: "Request Body",
        readonly: true,
        only: [:show]
      },
      response_headers: %{
        module: Backpex.Fields.Textarea,
        label: "Response Headers",
        readonly: true,
        only: [:show]
      },
      response_body: %{
        module: Backpex.Fields.Textarea,
        label: "Response Body",
        readonly: true,
        only: [:show]
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
        readonly: true,
        only: [:show]
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID",
        readonly: true,
        only: [:show]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "When"
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
