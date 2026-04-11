defmodule BlackboexWeb.Showcase.Sections.PlainKeyBanner do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Shared.PlainKeyBanner

  @code_reveal ~S"""
  <.plain_key_banner plain_key="bx_sk_live_abc123xyz789efg456hij012klm345nop678" />
  """

  @code_short ~S"""
  <.plain_key_banner plain_key="bx_sk_test_xyz" />
  """

  @code_usage ~S"""
  # In the LiveView, after creating the key:
  def handle_event("create_key", params, socket) do
    case ApiKeys.create_api_key(socket.assigns.scope, params) do
      {:ok, {api_key, plain_key}} ->
        {:noreply, assign(socket, plain_key: plain_key, api_key: api_key)}
      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # In the template — show banner only after creation:
  <.plain_key_banner :if={@plain_key} plain_key={@plain_key} />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_reveal, @code_reveal)
      |> assign(:code_short, @code_short)
      |> assign(:code_usage, @code_usage)

    ~H"""
    <.section_header
      title="Plain Key Banner"
      description="One-time API key reveal banner. Shown immediately after creating an API key — the plain text key is only visible once. Includes copy instructions and a prominent key display."
      module="BlackboexWeb.Components.Shared.PlainKeyBanner"
    />
    <div class="space-y-10">
      <.showcase_block title="API Key Reveal" code={@code_reveal}>
        <.plain_key_banner plain_key="bx_sk_live_abc123xyz789efg456hij012klm345nop678" />
      </.showcase_block>

      <.showcase_block title="Short Key (Test)" code={@code_short}>
        <.plain_key_banner plain_key="bx_sk_test_xyz" />
      </.showcase_block>

      <.showcase_block title="Usage Context (LiveView Pattern)" code={@code_usage}>
        <.panel class="p-4">
          <p class="text-sm text-muted-foreground">
            The banner is shown once after key creation. Store the
            <code class="text-xs bg-muted px-1 py-0.5 rounded">plain_key</code>
            in a socket assign and clear it when the user dismisses. The
            <code class="text-xs bg-muted px-1 py-0.5 rounded">dismiss_flash</code>
            event removes the banner.
          </p>
        </.panel>
      </.showcase_block>
    </div>
    """
  end
end
