defmodule BlackboexWeb.Components.Shared.PlainKeyBanner do
  @moduledoc """
  Banner shown after creating/rotating an API key, displaying the plain key for one-time copy.
  """

  use BlackboexWeb, :html

  attr :plain_key, :string, required: true

  @spec plain_key_banner(map()) :: Phoenix.LiveView.Rendered.t()
  def plain_key_banner(assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-primary bg-muted p-4 space-y-2">
      <p class="font-semibold text-foreground">
        Copy this key now — it won't be shown again:
      </p>
      <code class="block bg-accent text-accent-foreground p-2 rounded font-mono text-sm break-all select-all">
        {@plain_key}
      </code>
      <.button
        phx-click="dismiss_flash"
        variant="link"
        size="sm"
        class="text-primary hover:underline text-xs"
      >
        Dismiss
      </.button>
    </div>
    """
  end
end
