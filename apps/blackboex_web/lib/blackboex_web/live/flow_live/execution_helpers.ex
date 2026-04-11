defmodule BlackboexWeb.FlowLive.ExecutionHelpers do
  @moduledoc """
  Shared template helpers for flow execution views.
  """

  import BlackboexWeb.Components.StatusHelpers, only: [execution_status_classes: 1]

  @spec status_badge(String.t()) :: String.t()
  def status_badge("completed"), do: execution_status_classes("completed")
  def status_badge("failed"), do: execution_status_classes("failed")
  def status_badge("running"), do: execution_status_classes("running")
  def status_badge("halted"), do: execution_status_classes("halted")
  def status_badge(_), do: execution_status_classes("pending")

  @spec status_icon(String.t()) :: String.t()
  def status_icon("completed"), do: "hero-check-circle-mini"
  def status_icon("failed"), do: "hero-x-circle-mini"
  def status_icon("running"), do: "hero-arrow-path-mini"
  def status_icon("halted"), do: "hero-pause-circle-mini"
  def status_icon(_), do: "hero-question-mark-circle-mini"

  @spec short_id(String.t() | nil) :: String.t()
  def short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  def short_id(_), do: "—"

  @spec format_duration(integer() | nil) :: String.t()
  def format_duration(nil), do: "—"
  def format_duration(ms) when ms < 1000, do: "#{ms}ms"
  def format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  @spec format_time(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  def format_time(nil), do: "—"
  def format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
