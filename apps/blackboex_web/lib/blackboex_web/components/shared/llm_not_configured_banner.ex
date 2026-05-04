defmodule BlackboexWeb.Components.Shared.LlmNotConfiguredBanner do
  @moduledoc """
  Banner shown in AI-assist surfaces when the project has no Anthropic key
  configured. Deep-links to the LLM Integrations tab of the current project
  when enough context (org slug + project slug) is available.
  """

  use BlackboexWeb, :html

  @doc """
  Renders the banner.

  Passes either `project_url` (a fully resolved path to the integrations
  tab) or — when the URL cannot be resolved (e.g. context is loading) —
  the banner renders copy-only guidance.
  """
  attr :project_url, :string,
    default: nil,
    doc: "Target URL for the 'Configure' button (LLM Integrations tab)."

  attr :message, :string,
    default: "Anthropic API key is not configured for this project.",
    doc: "Main message shown above the CTA."

  @spec llm_not_configured_banner(map()) :: Phoenix.LiveView.Rendered.t()
  def llm_not_configured_banner(assigns) do
    ~H"""
    <div
      data-role="llm-not-configured-banner"
      class="rounded-lg border border-amber-300 bg-amber-50 text-amber-900 p-4 space-y-2"
    >
      <div class="flex items-start gap-2">
        <.icon name="hero-exclamation-triangle" class="h-5 w-5 mt-0.5" />
        <div class="space-y-1">
          <p class="font-semibold">{@message}</p>
          <p class="text-sm">
            AI assist (chat, generation, and code editing) is disabled until you
            configure the key in the project <strong>LLM Integrations</strong> tab.
          </p>
        </div>
      </div>
      <div :if={@project_url} class="pt-1">
        <.link
          navigate={@project_url}
          class="inline-flex items-center gap-1 text-sm font-medium text-amber-900 underline hover:text-amber-950"
        >
          Configure <.icon name="hero-arrow-right" class="h-4 w-4" />
        </.link>
      </div>
    </div>
    """
  end
end
