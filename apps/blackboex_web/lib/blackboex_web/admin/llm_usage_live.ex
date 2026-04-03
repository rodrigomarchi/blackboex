defmodule BlackboexWeb.Admin.LlmUsageLive do
  @moduledoc """
  Backpex LiveResource for viewing LLM usage records in the admin panel.
  Read-only.
  """

  alias Blackboex.LLM.Usage

  use Backpex.LiveResource,
    adapter_config: [
      schema: Usage,
      repo: Blackboex.Repo,
      update_changeset: &Usage.admin_changeset/3,
      create_changeset: &Usage.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "LLM Usage"

  @impl Backpex.LiveResource
  def plural_name, do: "LLM Usage"

  @impl Backpex.LiveResource
  def fields do
    [
      provider: %{
        module: Backpex.Fields.Text,
        label: "Provider",
        searchable: true
      },
      model: %{
        module: Backpex.Fields.Text,
        label: "Model",
        searchable: true
      },
      operation: %{
        module: Backpex.Fields.Text,
        label: "Operation",
        searchable: true
      },
      input_tokens: %{
        module: Backpex.Fields.Number,
        label: "Input Tokens"
      },
      output_tokens: %{
        module: Backpex.Fields.Number,
        label: "Output Tokens"
      },
      cost_cents: %{
        module: Backpex.Fields.Number,
        label: "Cost (cents)"
      },
      duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Duration (ms)"
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "When"
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
