defmodule BlackboexWeb.Logo do
  @moduledoc """
  Logo components for BlackBoex.

  Renders inline SVG logos that adapt to light/dark themes via `currentColor`.
  The logo is a hexagon (Hex/Elixir ecosystem) containing a stylized pipe
  operator `|>` (Elixir's data transformation symbol).

  ## Variants

  - `:icon` — Hexagon + pipe symbol only (32x32, for favicon, mobile)
  - `:full` — Icon + "BlackBoex" wordmark side by side
  - `:wordmark` — Text only: "Black" (regular) + "Boex" (bold)
  """
  use Phoenix.Component

  @doc """
  Renders the BlackBoex logo icon (hexagon with pipe operator).

  ## Examples

      <.logo_icon class="size-6" />
  """
  attr :class, :string, default: "size-6"
  attr :rest, :global

  def logo_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 32 32"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {@rest}
    >
      <path d="M16 3L27.3 9.5V22.5L16 29L4.7 22.5V9.5Z" />
      <line x1="11" y1="11" x2="11" y2="21" />
      <polyline points="15,11 21,16 15,21" />
    </svg>
    """
  end

  @doc """
  Renders the full BlackBoex logo (icon + wordmark).

  ## Examples

      <.logo_full class="h-7" />
  """
  attr :class, :string, default: "h-7"
  attr :rest, :global

  def logo_full(assigns) do
    ~H"""
    <a href="/" class={"flex items-center gap-2 #{@class}"} {@rest}>
      <svg
        class="h-full w-auto shrink-0"
        viewBox="0 0 32 32"
        fill="none"
        stroke="currentColor"
        stroke-width="1.75"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M16 3L27.3 9.5V22.5L16 29L4.7 22.5V9.5Z" />
        <line x1="11" y1="11" x2="11" y2="21" />
        <polyline points="15,11 21,16 15,21" />
      </svg>
      <span class="text-lg font-normal tracking-tight">
        Black<span class="font-bold">Boex</span>
      </span>
    </a>
    """
  end

  @doc """
  Renders only the BlackBoex wordmark (no icon).

  ## Examples

      <.logo_wordmark class="text-lg" />
  """
  attr :class, :string, default: "text-lg"
  attr :rest, :global

  def logo_wordmark(assigns) do
    ~H"""
    <span class={"font-normal tracking-tight #{@class}"} {@rest}>
      Black<span class="font-bold">Boex</span>
    </span>
    """
  end
end
