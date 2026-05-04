defmodule BlackboexWeb.Components.TypographyContractTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  @root Path.expand("../../../../..", __DIR__)
  @scan_roots [
    "apps/blackboex_web/lib",
    "apps/blackboex_web/assets/css",
    "apps/blackboex_web/assets/js"
  ]

  @excluded_path_parts [
    "/AGENTS.md",
    "/assets/vendor/",
    "/deps/",
    "/_build/",
    "/priv/static/"
  ]

  @disallowed_text_classes Regex.compile!(
                             "(^|[^[:alnum:]_:-])(?:[a-z]+:)*text-(?:micro|base|xl|3xl|[5-9]xl|\\[(?:9px|10px|11px)\\])(?=$|[^[:alnum:]_:/.-])"
                           )
  @responsive_font_size_classes Regex.compile!(
                                  "(^|[^[:alnum:]_:-])(?:sm|md|lg|xl|2xl):text-(?:2xs|xs|sm|base|lg|xl|[2-9]xl|\\[[^\\]]+\\])(?=$|[^[:alnum:]_:/.-])"
                                )
  @hardcoded_js_font_size Regex.compile!("fontSize:\\s*[\"'](?:8|9|10|11|12)px[\"']")
  @hardcoded_inline_font_size Regex.compile!("style=\"[^\"]*font-size:\\s*(?:8|9|10|11|12)px")
  @hardcoded_css_font_size Regex.compile!(
                             "font-size:\\s*\\d+(?:\\.\\d+)?(?:px|rem)(?:\\s*!important)?\\s*;"
                           )

  @allowed_hardcoded_css [
    {"apps/blackboex_web/assets/css/app.css", ~r/--font-size-/},
    {"apps/blackboex_web/assets/css/app.css", ~r/--content-font-/}
  ]

  test "web typography uses the approved font-size scale" do
    violations =
      @scan_roots
      |> Enum.flat_map(&Path.wildcard(Path.join([@root, &1, "**", "*"])))
      |> Enum.reject(&File.dir?/1)
      |> Enum.reject(&excluded?/1)
      |> Enum.flat_map(&file_violations/1)

    assert violations == []
  end

  defp excluded?(path) do
    relative = relative(path)
    Enum.any?(@excluded_path_parts, &String.contains?(relative, &1))
  end

  defp file_violations(path) do
    text = File.read!(path)

    [
      scan(path, text, @disallowed_text_classes, "uses a disallowed font-size utility"),
      scan(path, text, @responsive_font_size_classes, "uses a responsive font-size utility"),
      scan(path, text, @hardcoded_js_font_size, "uses a hardcoded JS fontSize"),
      scan(path, text, @hardcoded_inline_font_size, "uses an inline hardcoded font-size"),
      scan(path, text, @hardcoded_css_font_size, "uses a hardcoded CSS font-size")
    ]
    |> List.flatten()
  end

  defp scan(path, text, regex, message) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> Regex.match?(regex, line) end)
    |> Enum.reject(fn {line, _line_no} -> allowed_hardcoded_css?(path, line) end)
    |> Enum.map(fn {line, line_no} ->
      "#{relative(path)}:#{line_no} #{message}: #{String.trim(line)}"
    end)
  end

  defp allowed_hardcoded_css?(path, line) do
    relative = relative(path)

    Enum.any?(@allowed_hardcoded_css, fn {allowed_path, allowed_line} ->
      relative == allowed_path and Regex.match?(allowed_line, line)
    end)
  end

  defp relative(path), do: Path.relative_to(path, @root)
end
