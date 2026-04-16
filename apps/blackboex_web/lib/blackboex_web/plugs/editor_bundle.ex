defmodule BlackboexWeb.Plugs.EditorBundle do
  @moduledoc """
  Sets the `editor_bundle` assign on the conn based on the request path.

  Feature JS bundles (editor_tiptap.js, editor_code.js, editor_flow.js) are
  loaded conditionally in root.html.heex to avoid downloading heavy editor
  dependencies on pages that don't need them.
  """

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    assign(conn, :editor_bundle, detect_bundle(conn.path_info))
  end

  # Match path segments to determine which editor bundle to load.
  # path_info is a list of URL segments, e.g. ["orgs", "foo", "projects", "bar", "pages", "slug", "edit"]
  defp detect_bundle(segments) do
    segments
    |> Enum.zip(Stream.iterate(0, &(&1 + 1)))
    |> Enum.find_value(fn {segment, _idx} -> editor_for_segment(segment, segments) end)
  end

  defp editor_for_segment("pages", segments), do: if("edit" in segments, do: "editor_tiptap")
  defp editor_for_segment("flows", segments), do: if("edit" in segments, do: "editor_flow")
  defp editor_for_segment("playgrounds", segments), do: if("edit" in segments, do: "editor_code")
  defp editor_for_segment("apis", segments), do: if("edit" in segments, do: "editor_code")
  defp editor_for_segment(_, _segments), do: nil
end
