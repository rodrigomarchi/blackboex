defmodule BlackboexWeb.Admin.DailyUsageLive do
  @moduledoc """
  Backpex LiveResource for viewing daily usage records in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Billing.DailyUsage,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Billing.DailyUsage.admin_changeset/3,
      create_changeset: &Blackboex.Billing.DailyUsage.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Daily Usage"

  @impl Backpex.LiveResource
  def plural_name, do: "Daily Usage"

  @impl Backpex.LiveResource
  def fields do
    [
      date: %{
        module: Backpex.Fields.Date,
        label: "Date"
      },
      api_invocations: %{
        module: Backpex.Fields.Number,
        label: "API Invocations"
      },
      llm_generations: %{
        module: Backpex.Fields.Number,
        label: "LLM Generations"
      },
      tokens_input: %{
        module: Backpex.Fields.Number,
        label: "Input Tokens"
      },
      tokens_output: %{
        module: Backpex.Fields.Number,
        label: "Output Tokens"
      },
      llm_cost_cents: %{
        module: Backpex.Fields.Number,
        label: "LLM Cost (cents)"
      },
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
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
