defmodule BlackboexWeb.Components.Shared.DashboardHelpers do
  @moduledoc """
  Pure formatting helpers shared across all dashboard LiveViews.

  Import this module in dashboard LiveViews to get consistent number, cost,
  token, duration, and period formatting without duplicating the logic.
  """

  @doc "Human-readable period label for the given period key."
  @spec period_label(String.t()) :: String.t()
  def period_label("24h"), do: "today"
  def period_label("7d"), do: "7d"
  def period_label("30d"), do: "30d"
  def period_label(_), do: ""

  @doc "Format an integer or float as a comma-separated number string."
  @spec format_number(number() | nil) :: String.t()
  def format_number(nil), do: "0"

  def format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map_join(",", &Enum.join/1)
  end

  def format_number(n) when is_float(n), do: format_number(trunc(n))

  @doc "Format a cost value in cents as a dollar string."
  @spec format_cost(non_neg_integer() | nil) :: String.t()
  def format_cost(nil), do: "$0.00"
  def format_cost(0), do: "$0.00"
  def format_cost(cents) when is_integer(cents), do: "$#{Float.round(cents / 100, 2)}"

  @doc "Format a token count with K/M suffix."
  @spec format_tokens(non_neg_integer() | nil) :: String.t()
  def format_tokens(nil), do: "0"
  def format_tokens(0), do: "0"

  def format_tokens(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  def format_tokens(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  def format_tokens(n) when is_integer(n), do: Integer.to_string(n)

  @doc "Format a duration in milliseconds as a human-readable string."
  @spec format_duration(Decimal.t() | float() | integer() | nil) :: String.t()
  def format_duration(nil), do: "-"

  def format_duration(%Decimal{} = ms), do: ms |> Decimal.to_float() |> format_duration()

  def format_duration(ms) when is_number(ms) and ms >= 60_000,
    do: "#{div(trunc(ms), 60_000)}m #{rem(div(trunc(ms), 1000), 60)}s"

  def format_duration(ms) when is_number(ms) and ms >= 1000,
    do: "#{Float.round(ms / 1000, 1)}s"

  def format_duration(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  def format_duration(ms) when is_integer(ms), do: "#{ms}ms"

  @doc "Format a latency value in milliseconds, returning a placeholder for nil."
  @spec format_latency(float() | integer() | nil) :: String.t()
  def format_latency(nil), do: "--"
  def format_latency(ms) when is_number(ms) and ms < 1, do: "<1ms"
  def format_latency(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  def format_latency(ms) when is_integer(ms), do: "#{ms}ms"
end
