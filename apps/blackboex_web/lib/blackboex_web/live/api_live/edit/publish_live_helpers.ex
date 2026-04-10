defmodule BlackboexWeb.ApiLive.Edit.PublishLiveHelpers do
  @moduledoc """
  Pure helper functions for PublishLive.
  No socket access — safe to call from templates and event handlers alike.
  """

  # ── Confirm dialog ────────────────────────────────────────────────────

  @spec build_confirm(String.t() | nil, map()) :: map() | nil
  def build_confirm("unpublish", _params) do
    %{
      title: "Unpublish API?",
      description:
        "The API will no longer be accessible to consumers. You can republish it later.",
      variant: :warning,
      confirm_label: "Unpublish",
      event: "unpublish",
      meta: %{}
    }
  end

  def build_confirm("publish_version", params) do
    %{
      title: "Publish this version?",
      description:
        "This will make it the live version. The current published version will be replaced.",
      variant: :info,
      confirm_label: "Publish",
      event: "publish_version",
      meta: Map.take(params, ["number"])
    }
  end

  def build_confirm(_, _), do: nil

  # ── Version predicates ────────────────────────────────────────────────

  @spec published_version?(map(), map() | nil) :: boolean()
  def published_version?(_version, nil), do: false

  def published_version?(version, published),
    do: version.version_number == published.version_number

  @spec can_publish_version?(map(), map() | nil, String.t()) :: boolean()
  def can_publish_version?(version, published_version, api_status) do
    version.compilation_status == "success" and
      api_status in ["compiled", "published"] and
      not published_version?(version, published_version)
  end

  # ── Display helpers ───────────────────────────────────────────────────

  @spec compilation_status_classes(String.t()) :: String.t()
  def compilation_status_classes("success"), do: "bg-success/10 text-success-foreground"
  def compilation_status_classes("error"), do: "bg-destructive/10 text-destructive"
  def compilation_status_classes(_), do: "bg-muted text-muted-foreground"

  @spec compilation_status_label(String.t()) :: String.t()
  def compilation_status_label("success"), do: "Compiled"
  def compilation_status_label("error"), do: "Failed"
  def compilation_status_label(_), do: "Pending"

  @spec humanize_source(String.t()) :: String.t()
  def humanize_source("manual_edit"), do: "manual edit"
  def humanize_source("chat_edit"), do: "chat edit"
  def humanize_source(source), do: source
end
