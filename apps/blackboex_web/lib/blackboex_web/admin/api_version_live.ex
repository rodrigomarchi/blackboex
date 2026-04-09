defmodule BlackboexWeb.Admin.ApiVersionLive do
  @moduledoc """
  Backpex LiveResource for viewing API versions in the admin panel.
  Read-only.
  """

  alias Blackboex.Apis.ApiVersion

  use Backpex.LiveResource,
    adapter_config: [
      schema: ApiVersion,
      repo: Blackboex.Repo,
      update_changeset: &ApiVersion.admin_changeset/3,
      create_changeset: &ApiVersion.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "API Version"

  @impl Backpex.LiveResource
  def plural_name, do: "API Versions"

  @impl Backpex.LiveResource
  def fields do
    [
      version_number: %{
        module: Backpex.Fields.Number,
        label: "Version"
      },
      source: %{
        module: Backpex.Fields.Select,
        label: "Source",
        options: [
          Generation: "generation",
          "Manual Edit": "manual_edit",
          "Chat Edit": "chat_edit",
          Rollback: "rollback"
        ]
      },
      compilation_status: %{
        module: Backpex.Fields.Select,
        label: "Compilation",
        options: [Pending: "pending", Success: "success", Error: "error"]
      },
      prompt: %{
        module: Backpex.Fields.Textarea,
        label: "Prompt"
      },
      compilation_errors: %{
        module: Backpex.Fields.Text,
        label: "Compilation Errors",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          errors = Map.get(assigns.item, :compilation_errors) || []

          text =
            if errors == [],
              do: "None",
              else: Enum.join(errors, "\n")

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <div
            id="admin-apiversion-errors"
            phx-hook="CodeEditor"
            data-language="json"
            data-readonly="true"
            data-minimal="true"
            data-value={@text}
            class="rounded-md overflow-hidden border [&_.cm-editor]:max-h-96"
            phx-update="ignore"
          />
          """
        end
      },
      diff_summary: %{
        module: Backpex.Fields.Textarea,
        label: "Diff Summary"
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
      },
      created_by_id: %{
        module: Backpex.Fields.Text,
        label: "Created By"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created"
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
