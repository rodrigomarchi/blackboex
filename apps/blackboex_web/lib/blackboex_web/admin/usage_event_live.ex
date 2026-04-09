defmodule BlackboexWeb.Admin.UsageEventLive do
  @moduledoc """
  Backpex LiveResource for viewing usage events in the admin panel.
  Read-only.
  """

  alias Blackboex.Billing.UsageEvent

  use Backpex.LiveResource,
    adapter_config: [
      schema: UsageEvent,
      repo: Blackboex.Repo,
      update_changeset: &UsageEvent.admin_changeset/3,
      create_changeset: &UsageEvent.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin},
    init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Usage Event"

  @impl Backpex.LiveResource
  def plural_name, do: "Usage Events"

  @impl Backpex.LiveResource
  def fields do
    [
      event_type: %{
        module: Backpex.Fields.Select,
        label: "Event Type",
        options: ["API Invocation": "api_invocation", "LLM Generation": "llm_generation"]
      },
      metadata: %{
        module: Backpex.Fields.Text,
        label: "Metadata",
        readonly: true,
        only: [:show],
        render: fn assigns ->
          value = Map.get(assigns.item, :metadata)

          text =
            if is_map(value) or is_list(value),
              do: inspect(value, pretty: true, limit: :infinity),
              else: to_string(value || "")

          assigns = Phoenix.Component.assign(assigns, :text, text)

          ~H"""
          <div
            id="admin-usage-metadata"
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
      organization_id: %{
        module: Backpex.Fields.Text,
        label: "Organization ID"
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
