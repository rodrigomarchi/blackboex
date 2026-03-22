defmodule BlackboexWeb.Admin.MetricRollupLive do
  @moduledoc """
  Backpex LiveResource for viewing API metric rollups in the admin panel.
  Read-only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Blackboex.Apis.MetricRollup,
      repo: Blackboex.Repo,
      update_changeset: &Blackboex.Apis.MetricRollup.admin_changeset/3,
      create_changeset: &Blackboex.Apis.MetricRollup.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Metric Rollup"

  @impl Backpex.LiveResource
  def plural_name, do: "Metric Rollups"

  @impl Backpex.LiveResource
  def fields do
    [
      date: %{
        module: Backpex.Fields.Date,
        label: "Date"
      },
      hour: %{
        module: Backpex.Fields.Number,
        label: "Hour"
      },
      invocations: %{
        module: Backpex.Fields.Number,
        label: "Invocations"
      },
      errors: %{
        module: Backpex.Fields.Number,
        label: "Errors"
      },
      avg_duration_ms: %{
        module: Backpex.Fields.Number,
        label: "Avg Duration (ms)"
      },
      p95_duration_ms: %{
        module: Backpex.Fields.Number,
        label: "P95 Duration (ms)",
        only: [:show]
      },
      unique_consumers: %{
        module: Backpex.Fields.Number,
        label: "Unique Consumers"
      },
      api_id: %{
        module: Backpex.Fields.Text,
        label: "API ID",
        readonly: true,
        only: [:show]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:show]
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
