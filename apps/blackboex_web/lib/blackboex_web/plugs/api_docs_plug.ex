defmodule BlackboexWeb.Plugs.ApiDocsPlug do
  @moduledoc """
  Serves OpenAPI spec (JSON/YAML) and Swagger UI for published APIs.
  Only serves docs for published, public APIs.
  """

  import Plug.Conn

  alias Blackboex.Apis.Api
  alias Blackboex.Docs.OpenApiGenerator

  @spec serve_spec_json(Plug.Conn.t(), Api.t(), String.t(), String.t()) :: Plug.Conn.t()
  def serve_spec_json(conn, %Api{} = api, org_slug, slug) do
    spec = build_spec(api, conn, org_slug, slug)
    json = OpenApiGenerator.to_json(spec)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, json)
    |> halt()
  end

  @spec serve_spec_yaml(Plug.Conn.t(), Api.t(), String.t(), String.t()) :: Plug.Conn.t()
  def serve_spec_yaml(conn, %Api{} = api, org_slug, slug) do
    spec = build_spec(api, conn, org_slug, slug)
    yaml = OpenApiGenerator.to_yaml(spec)

    conn
    |> put_resp_content_type("text/yaml")
    |> send_resp(200, yaml)
    |> halt()
  end

  @spec serve_swagger_ui(Plug.Conn.t(), Api.t(), String.t(), String.t()) :: Plug.Conn.t()
  def serve_swagger_ui(conn, %Api{} = api, org_slug, slug) do
    spec_url = "/api/#{org_slug}/#{slug}/openapi.json"
    html = swagger_ui_html(api.name, spec_url)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
    |> halt()
  end

  defp build_spec(api, conn, org_slug, slug) do
    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}/api/#{org_slug}/#{slug}"
    OpenApiGenerator.generate(api, base_url: base_url)
  end

  defp swagger_ui_html(title, spec_url) do
    """
    <!DOCTYPE html>
    <html lang="en" data-theme="">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{html_escape(title)} - API Documentation</title>
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <style>
        /* Reset: isolate from any parent theme */
        *, *::before, *::after { color-scheme: light; }
        html, body {
          margin: 0;
          padding: 0;
          background: #fafafa;
          color: #3b4151;
          font-family: sans-serif;
        }
        .swagger-ui .topbar { display: none; }
        .swagger-ui { max-width: 1200px; margin: 0 auto; padding: 20px; }
      </style>
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        SwaggerUIBundle({
          url: "#{spec_url}",
          dom_id: '#swagger-ui',
          presets: [SwaggerUIBundle.presets.apis],
          layout: 'BaseLayout',
          deepLinking: true,
          tryItOutEnabled: true,
          syntaxHighlight: { theme: 'agate' }
        });
      </script>
    </body>
    </html>
    """
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
