defmodule BlackboexWeb.FlowLive.IndexHelpers do
  @moduledoc """
  Pure helper functions for the flows index LiveView.
  No socket access — safe to call from both LiveView and components.
  """

  alias Blackboex.Flows.Templates

  @spec get_first_category() :: String.t() | nil
  def get_first_category do
    case Templates.list_by_category() do
      [{cat, _} | _] -> cat
      [] -> nil
    end
  end

  @spec build_confirm(String.t(), map()) :: map() | nil
  def build_confirm("delete", params) do
    %{
      title: "Delete flow?",
      description:
        "This action cannot be undone. The flow and all its data will be permanently removed.",
      variant: :danger,
      confirm_label: "Delete",
      event: "delete",
      meta: Map.take(params, ["id"])
    }
  end

  def build_confirm(_, _), do: nil

  @spec flow_status_classes(String.t()) :: String.t()
  def flow_status_classes("draft"), do: "bg-muted text-muted-foreground"

  def flow_status_classes("active"),
    do: "bg-status-active/15 text-status-active-foreground"

  def flow_status_classes("archived"),
    do: "bg-status-archived/15 text-status-archived-foreground"

  def flow_status_classes(_), do: "bg-muted text-muted-foreground"

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  def format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
