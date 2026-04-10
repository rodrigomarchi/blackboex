defmodule BlackboexWeb.ApiLive.IndexHelpers do
  @moduledoc """
  Pure helper functions for the API index LiveView.
  No socket access — safe to call from components and event handlers.
  """

  # ── Confirm Dialog ───────────────────────────────────────────────────────

  @spec build_confirm(String.t(), map()) :: map() | nil
  def build_confirm("delete", params) do
    %{
      title: "Delete API?",
      description:
        "This action cannot be undone. The API and all its versions will be permanently removed.",
      variant: :danger,
      confirm_label: "Delete",
      event: "delete",
      meta: Map.take(params, ["id"])
    }
  end

  def build_confirm(_, _), do: nil

  # ── Formatters ───────────────────────────────────────────────────────────

  @spec format_latency(number() | nil) :: String.t()
  def format_latency(nil), do: "--"
  def format_latency(ms) when ms < 1, do: "<1ms"
  def format_latency(ms), do: "#{round(ms)}ms"

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
