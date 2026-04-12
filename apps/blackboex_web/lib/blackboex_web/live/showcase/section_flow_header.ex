defmodule BlackboexWeb.Showcase.Sections.FlowHeader do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.FlowEditor.FlowHeader

  @code_default ~S"""
  <.flow_header
    flow={%{
      name: "User Onboarding Flow",
      slug: "user-onboarding",
      status: "draft",
      id: "flow-1",
      webhook_token: "tok_abc123def456"
    }}
    saving={false}
    saved={false}
  />
  """

  @code_saving ~S"""
  <.flow_header
    flow={%{
      name: "User Onboarding Flow",
      slug: "user-onboarding",
      status: "active",
      id: "flow-1",
      webhook_token: "tok_abc123def456"
    }}
    saving={true}
    saved={false}
  />
  """

  @code_saved ~S"""
  <.flow_header
    flow={%{
      name: "User Onboarding Flow",
      slug: "user-onboarding",
      status: "active",
      id: "flow-1",
      webhook_token: "tok_abc123def456"
    }}
    saving={false}
    saved={true}
  />
  """

  @flow_draft %{
    name: "User Onboarding Flow",
    slug: "user-onboarding",
    status: "draft",
    id: "flow-1",
    webhook_token: "tok_abc123def456"
  }

  @flow_active %{
    name: "User Onboarding Flow",
    slug: "user-onboarding",
    status: "active",
    id: "flow-1",
    webhook_token: "tok_abc123def456"
  }

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_default, @code_default)
      |> assign(:code_saving, @code_saving)
      |> assign(:code_saved, @code_saved)
      |> assign(:flow_draft, @flow_draft)
      |> assign(:flow_active, @flow_active)

    ~H"""
    <.section_header
      title="FlowHeader"
      description="Header bar for the flow editor. Shows the flow name, save status indicator (saving/saved/unsaved), and action buttons."
      module="BlackboexWeb.Components.FlowEditor.FlowHeader"
    />
    <div class="space-y-10">
      <.showcase_block title="Default (unsaved, draft status)" code={@code_default}>
        <div class="rounded-lg overflow-hidden border -mx-6 -mt-6 mb-0">
          <.flow_header flow={@flow_draft} saving={false} saved={false} />
        </div>
      </.showcase_block>

      <.showcase_block title="Saving state (active flow)" code={@code_saving}>
        <div class="rounded-lg overflow-hidden border -mx-6 -mt-6 mb-0">
          <.flow_header flow={@flow_active} saving={true} saved={false} />
        </div>
      </.showcase_block>

      <.showcase_block title="Saved state (active flow)" code={@code_saved}>
        <div class="rounded-lg overflow-hidden border -mx-6 -mt-6 mb-0">
          <.flow_header flow={@flow_active} saving={false} saved={true} />
        </div>
      </.showcase_block>

      <.showcase_block title="Mock flow data — active with full webhook">
        <div class="rounded-lg overflow-hidden border -mx-6 -mt-6 mb-0">
          <.flow_header
            flow={
              %{
                name: "Payment Retry Automation",
                slug: "payment-retry",
                status: "active",
                id: "flow-2",
                webhook_token: "tok_xyz789uvw012"
              }
            }
            saving={false}
            saved={false}
          />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
