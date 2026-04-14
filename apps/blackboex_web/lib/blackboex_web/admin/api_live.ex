defmodule BlackboexWeb.Admin.ApiLive do
  @moduledoc """
  Backpex LiveResource for managing APIs in the admin panel.
  """

  alias Blackboex.Apis.Api

  use Backpex.LiveResource,
    adapter_config: [
      schema: Api,
      repo: Blackboex.Repo,
      update_changeset: &Api.admin_changeset/3,
      create_changeset: &Api.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  import BlackboexWeb.Components.Shared.CodeEditorField

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
        label: "Slug"
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        options: [
          Draft: "draft",
          Compiled: "compiled",
          Published: "published",
          Archived: "archived"
        ]
      },
      visibility: %{
        module: Backpex.Fields.Select,
        label: "Visibility",
        options: [Private: "private", Public: "public"]
      },
      description: %{
        module: Backpex.Fields.Text,
        label: "Description"
      },
      template_type: %{
        module: Backpex.Fields.Select,
        label: "Template Type",
        options: [Computation: "computation", CRUD: "crud", Webhook: "webhook"]
      },
      method: %{
        module: Backpex.Fields.Select,
        label: "HTTP Method",
        options: [GET: "GET", POST: "POST", PUT: "PUT", PATCH: "PATCH", DELETE: "DELETE"]
      },
      requires_auth: %{
        module: Backpex.Fields.Boolean,
        label: "Requires Auth"
      },
      documentation_md: %{
        module: Backpex.Fields.Textarea,
        label: "Documentation"
      },
      param_schema: %{
        module: Backpex.Fields.Text,
        label: "Param Schema",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :param_schema)

          text =
            if is_map(value) and value != %{},
              do: Jason.encode!(value, pretty: true),
              else: "—"

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <.code_editor_field id="admin-param-schema" value={@text} />
          """
        end
      },
      example_request: %{
        module: Backpex.Fields.Text,
        label: "Example Request",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :example_request)

          text =
            if is_map(value) and value != %{},
              do: Jason.encode!(value, pretty: true),
              else: "—"

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <.code_editor_field id="admin-example-request" value={@text} />
          """
        end
      },
      example_response: %{
        module: Backpex.Fields.Text,
        label: "Example Response",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :example_response)

          text =
            if is_map(value) and value != %{},
              do: Jason.encode!(value, pretty: true),
              else: "—"

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <.code_editor_field id="admin-example-response" value={@text} />
          """
        end
      },
      project_id: %{
        module: Backpex.Fields.Text,
        label: "Project ID"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
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
