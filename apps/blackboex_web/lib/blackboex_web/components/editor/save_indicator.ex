defmodule BlackboexWeb.Components.Editor.SaveIndicator do
  @moduledoc """
  Tiny inline indicator showing auto-save state (saved, saving, unsaved).
  """

  use Phoenix.Component

  attr :status, :atom, values: [:saved, :saving, :unsaved], default: :saved

  @spec save_indicator(map()) :: Phoenix.LiveView.Rendered.t()
  def save_indicator(assigns) do
    ~H"""
    <span class={["text-2xs", status_class(@status)]}>
      {status_text(@status)}
    </span>
    """
  end

  defp status_class(:saved), do: "text-muted-foreground"
  defp status_class(:saving), do: "text-accent-amber"
  defp status_class(:unsaved), do: "text-accent-amber"

  defp status_text(:saved), do: "Saved"
  defp status_text(:saving), do: "Saving..."
  defp status_text(:unsaved), do: "Unsaved"
end
