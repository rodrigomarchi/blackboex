defmodule BlackboexWeb.Admin.LlmUsageLive do
  @moduledoc """
  Backpex LiveResource for viewing LLM usage records in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.LLM.Usage,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.LLM.Usage.admin_changeset/3,
      create_changeset: &Blackboex.LLM.Usage.admin_changeset/3
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
        label: "Duration (ms)",
        only: [:show]
      },
      user_id: %{
        module: Backpex.Fields.Text,
        label: "User ID",
        readonly: true,
        only: [:show]
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID",
        readonly: true,
        only: [:show]
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
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
