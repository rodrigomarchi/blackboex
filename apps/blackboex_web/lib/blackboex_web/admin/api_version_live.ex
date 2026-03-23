defmodule BlackboexWeb.Admin.ApiVersionLive do
  @moduledoc """
  Backpex LiveResource for viewing API versions in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Apis.ApiVersion,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Apis.ApiVersion.admin_changeset/3,
      create_changeset: &Blackboex.Apis.ApiVersion.admin_changeset/3
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
      code: %{
        module: Backpex.Fields.Textarea,
        label: "Code"
      },
      test_code: %{
        module: Backpex.Fields.Textarea,
        label: "Test Code"
      },
      prompt: %{
        module: Backpex.Fields.Textarea,
        label: "Prompt"
      },
      llm_response: %{
        module: Backpex.Fields.Textarea,
        label: "LLM Response"
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
          <pre class="text-xs whitespace-pre-wrap max-h-96 overflow-auto"><%= @text %></pre>
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
