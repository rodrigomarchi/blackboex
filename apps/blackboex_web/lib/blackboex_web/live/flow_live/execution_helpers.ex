defmodule BlackboexWeb.FlowLive.ExecutionHelpers do
  @moduledoc """
  Shared template helpers for flow execution views.

  Node type metadata (icon, color, label) is derived from the canonical
  `EditHelpers.node_types/0` — no duplication.
  """

  import BlackboexWeb.Components.StatusHelpers, only: [execution_status_classes: 1]

  alias BlackboexWeb.FlowLive.EditHelpers

  # Derived from the canonical node type list — single source of truth
  @node_type_meta Map.new(EditHelpers.node_types(), fn n ->
                    {n.type, %{icon: n.icon, color: n.color, label: n.label}}
                  end)

  # ── Node type helpers ─────────────────────────────────────────────────

  @spec node_icon(String.t()) :: %{icon: String.t(), color: String.t(), label: String.t()}
  def node_icon(type),
    do: Map.get(@node_type_meta, type, %{icon: "hero-cube", color: "#6b7280", label: type})

  @spec format_json(any()) :: String.t()
  def format_json(nil), do: "—"
  def format_json(data), do: Jason.encode!(data, pretty: true)

  # ── Status helpers ────────────────────────────────────────────────────

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

  # ── Formatting helpers ────────────────────────────────────────────────

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
