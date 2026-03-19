defmodule Blackboex.Testing.SnippetGenerator do
  @moduledoc """
  Generates code snippets for consuming an API in various programming languages.
  All user-controlled values are properly escaped for each target language.
  """

  @valid_languages ~w(curl python javascript elixir ruby go)a

  @spec generate(map(), atom(), map()) :: String.t()
  def generate(_api, :curl, request), do: generate_curl(request)
  def generate(_api, :python, request), do: generate_python(request)
  def generate(_api, :javascript, request), do: generate_javascript(request)
  def generate(_api, :elixir, request), do: generate_elixir(request)
  def generate(_api, :ruby, request), do: generate_ruby(request)
  def generate(_api, :go, request), do: generate_go(request)

  @spec valid_language?(atom()) :: boolean()
  def valid_language?(lang), do: lang in @valid_languages

  # --- cURL ---

  defp generate_curl(request) do
    parts = ["curl -X #{shell_escape(request.method)} #{shell_escape(request.url)}"]

    parts = parts ++ curl_header_flags(request)

    parts =
      if has_body?(request) do
        parts ++ ["-d #{shell_escape(request.body)}"]
      else
        parts
      end

    Enum.join(parts, " \\\n  ")
  end

  defp curl_header_flags(request) do
    build_headers_map(request)
    |> Enum.map(fn {k, v} -> "-H #{shell_escape("#{k}: #{v}")}" end)
  end

  # Shell escaping: wrap in single quotes and escape internal single quotes
  # 'it'\''s safe' → shell interprets as: it's safe
  defp shell_escape(value) when is_binary(value) do
    escaped = String.replace(value, "'", "'\\''")
    "'#{escaped}'"
  end

  defp shell_escape(nil), do: "''"

  # --- Python ---

  defp generate_python(request) do
    method = String.downcase(request.method)
    headers = build_headers_map(request)

    lines = [
      "import requests",
      "",
      "response = requests.#{method}(",
      "    #{python_string(request.url)},"
    ]

    lines = lines ++ ["    headers=#{python_dict(headers)},"]

    lines =
      if has_body?(request) do
        lines ++ ["    json=#{request.body},"]
      else
        lines
      end

    lines = lines ++ [")", "", "print(response.json())"]
    Enum.join(lines, "\n")
  end

  defp python_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("'", "\\'")

    "'#{escaped}'"
  end

  defp python_dict(map) do
    pairs =
      Enum.map(map, fn {k, v} -> "#{python_string(k)}: #{python_string(v)}" end)
      |> Enum.join(", ")

    "{#{pairs}}"
  end

  # --- JavaScript ---

  defp generate_javascript(request) do
    headers = build_headers_map(request)

    options =
      [
        "    method: #{js_string(request.method)}",
        "    headers: #{js_object(headers)}"
      ] ++
        if has_body?(request) do
          ["    body: JSON.stringify(#{request.body})"]
        else
          []
        end

    """
    const response = await fetch(#{js_string(request.url)}, {
    #{Enum.join(options, ",\n")},
    });

    const data = await response.json();
    console.log(data);\
    """
  end

  defp js_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("'", "\\'")
      |> String.replace("\n", "\\n")

    "'#{escaped}'"
  end

  defp js_object(map) do
    pairs =
      Enum.map(map, fn {k, v} -> "#{js_string(k)}: #{js_string(v)}" end)
      |> Enum.join(", ")

    "{#{pairs}}"
  end

  # --- Elixir ---

  defp generate_elixir(request) do
    method = String.downcase(request.method)
    headers = build_headers_list(request)
    headers_str = inspect(headers)

    body_part =
      if has_body?(request) do
        "\n  body: #{inspect(request.body)},"
      else
        ""
      end

    """
    {:ok, response} = Req.#{method}(
      #{inspect(request.url)},
      headers: #{headers_str},#{body_part}
    )

    IO.inspect(response.body)\
    """
  end

  # --- Ruby ---

  defp generate_ruby(request) do
    headers = build_headers_map(request)

    body_part =
      if has_body?(request) do
        "\nrequest.body = #{ruby_string(request.body)}"
      else
        ""
      end

    headers_lines =
      Enum.map(headers, fn {k, v} -> "request[#{ruby_string(k)}] = #{ruby_string(v)}" end)
      |> Enum.join("\n")

    """
    require 'net/http'
    require 'json'

    uri = URI(#{ruby_string(request.url)})
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::#{ruby_method(request.method)}.new(uri)
    #{headers_lines}#{body_part}

    response = http.request(request)
    puts JSON.parse(response.body)\
    """
  end

  defp ruby_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("'", "\\'")

    "'#{escaped}'"
  end

  # --- Go ---

  defp generate_go(request) do
    body_setup =
      if has_body?(request) do
        escaped_body = go_escape_backtick(request.body)

        """
        \tbody := strings.NewReader(`#{escaped_body}`)
        \treq, err := http.NewRequest(#{go_string(request.method)}, #{go_string(request.url)}, body)\
        """
      else
        """
        \treq, err := http.NewRequest(#{go_string(request.method)}, #{go_string(request.url)}, nil)\
        """
      end

    headers = build_headers_map(request)

    headers_lines =
      Enum.map(headers, fn {k, v} ->
        "\treq.Header.Set(#{go_string(k)}, #{go_string(v)})"
      end)
      |> Enum.join("\n")

    imports =
      if has_body?(request) do
        "\"fmt\"\n\t\"io\"\n\t\"net/http\"\n\t\"strings\""
      else
        "\"fmt\"\n\t\"io\"\n\t\"net/http\""
      end

    """
    package main

    import (
    \t#{imports}
    )

    func main() {
    #{body_setup}
    \tif err != nil {
    \t\tpanic(err)
    \t}

    #{headers_lines}

    \tclient := &http.Client{}
    \tresp, err := client.Do(req)
    \tif err != nil {
    \t\tpanic(err)
    \t}
    \tdefer resp.Body.Close()

    \tdata, _ := io.ReadAll(resp.Body)
    \tfmt.Println(string(data))
    }\
    """
  end

  defp go_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end

  # Go backtick strings can't contain backticks — use string concat as escape
  defp go_escape_backtick(value) do
    String.replace(value, "`", "` + \"`\" + `")
  end

  # --- Shared helpers ---

  defp has_body?(request), do: request[:body] != nil and request[:body] != ""

  defp build_headers_map(request) do
    base =
      (request[:headers] || [])
      |> Enum.map(fn {k, v} -> {format_header_key(k), v} end)
      |> Map.new()

    if api_key = request[:api_key] do
      Map.put(base, "X-Api-Key", api_key)
    else
      base
    end
  end

  defp build_headers_list(request) do
    base = request[:headers] || []

    if api_key = request[:api_key] do
      base ++ [{"x-api-key", api_key}]
    else
      base
    end
  end

  defp format_header_key(key) do
    key
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("-")
  end

  defp ruby_method("GET"), do: "Get"
  defp ruby_method("POST"), do: "Post"
  defp ruby_method("PUT"), do: "Put"
  defp ruby_method("PATCH"), do: "Patch"
  defp ruby_method("DELETE"), do: "Delete"
  defp ruby_method(method), do: String.capitalize(method)
end
