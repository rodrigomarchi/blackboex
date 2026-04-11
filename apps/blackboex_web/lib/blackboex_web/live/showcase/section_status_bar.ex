defmodule BlackboexWeb.Showcase.Sections.StatusBar do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.StatusBar

  @code_basic ~S"""
  <.status_bar api={%{name: "Payment API", slug: "payment-api", status: "draft"}} />
  """

  @code_versions ~S"""
  <.status_bar
    api={%{name: "Payment API", slug: "payment-api", status: "published"}}
    versions={[
      %{version_number: "1.3.0"},
      %{version_number: "1.2.0"},
      %{version_number: "1.1.0"}
    ]}
    selected_version={%{version_number: "1.2.0"}}
  />
  """

  @code_statuses ~S"""
  <div class="space-y-1">
    <.status_bar api={%{name: "Payment API", slug: "payment-api", status: "draft"}} />
    <.status_bar api={%{name: "Payment API", slug: "payment-api", status: "compiled"}} />
    <.status_bar api={%{name: "Payment API", slug: "payment-api", status: "published"}} />
  </div>
  """

  @api_draft %{name: "Payment API", slug: "payment-api", status: "draft"}
  @api_compiled %{name: "Payment API", slug: "payment-api", status: "compiled"}
  @api_published %{name: "Payment API", slug: "payment-api", status: "published"}

  @versions [
    %{version_number: "1.3.0"},
    %{version_number: "1.2.0"},
    %{version_number: "1.1.0"}
  ]

  @selected_version %{version_number: "1.2.0"}

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_versions, @code_versions)
      |> assign(:code_statuses, @code_statuses)
      |> assign(:api_draft, @api_draft)
      |> assign(:api_compiled, @api_compiled)
      |> assign(:api_published, @api_published)
      |> assign(:versions, @versions)
      |> assign(:selected_version, @selected_version)

    ~H"""
    <.section_header
      title="StatusBar"
      description="Editor status bar showing API metadata, version selector, and deployment status. Renders at the bottom of the API code editor."
      module="BlackboexWeb.Components.Editor.StatusBar"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic status bar" code={@code_basic}>
        <.status_bar api={@api_draft} />
      </.showcase_block>

      <.showcase_block title="With versions and selected version" code={@code_versions}>
        <.status_bar
          api={@api_published}
          versions={@versions}
          selected_version={@selected_version}
        />
      </.showcase_block>

      <.showcase_block title="Different API statuses" code={@code_statuses}>
        <div class="space-y-1">
          <.status_bar api={@api_draft} />
          <.status_bar api={@api_compiled} />
          <.status_bar api={@api_published} />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
