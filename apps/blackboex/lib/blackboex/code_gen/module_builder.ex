defmodule Blackboex.CodeGen.ModuleBuilder do
  @moduledoc """
  Builds Plug module source code from handler code and a template type.

  Generates complete Plug.Router modules that can be compiled and served
  as dynamic API endpoints.
  """

  @spec build_module(atom(), String.t(), atom()) :: {:ok, String.t()}
  def build_module(module_name, handler_code, template_type) do
    code = build_template(module_name, handler_code, template_type)
    {:ok, code}
  end

  defp build_template(module_name, handler_code, :computation) do
    """
    defmodule #{inspect(module_name)} do
      use Plug.Router

      plug :match
      plug Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["*/*"]
      plug :put_json_content_type
      plug :dispatch

      defp put_json_content_type(conn, _opts), do: put_resp_content_type(conn, "application/json")

      post "/" do
        try do
          params = conn.body_params
          result = handle(params)
          send_resp(conn, 200, Jason.encode!(result))
        rescue
          e -> send_resp(conn, 500, Jason.encode!(%{error: "handler error", detail: Exception.message(e)}))
        end
      end

      get "/" do
        send_resp(conn, 200, Jason.encode!(%{status: "ok", type: "computation"}))
      end

      match _ do
        send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      end

    #{indent(handler_code, 2)}
    end
    """
  end

  defp build_template(module_name, handler_code, :crud) do
    """
    defmodule #{inspect(module_name)} do
      use Plug.Router

      plug :match
      plug Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["*/*"]
      plug :put_json_content_type
      plug :dispatch

      defp put_json_content_type(conn, _opts), do: put_resp_content_type(conn, "application/json")

      defp safe_call(conn, fun) do
        try do
          fun.()
        rescue
          e -> send_resp(conn, 500, Jason.encode!(%{error: "handler error", detail: Exception.message(e)}))
        end
      end

      get "/" do
        safe_call(conn, fn ->
          result = handle_list(conn.query_params)
          send_resp(conn, 200, Jason.encode!(result))
        end)
      end

      get "/:id" do
        safe_call(conn, fn ->
          result = handle_get(id, conn.query_params)
          send_resp(conn, 200, Jason.encode!(result))
        end)
      end

      post "/" do
        safe_call(conn, fn ->
          result = handle_create(conn.body_params)
          send_resp(conn, 201, Jason.encode!(result))
        end)
      end

      put "/:id" do
        safe_call(conn, fn ->
          result = handle_update(id, conn.body_params)
          send_resp(conn, 200, Jason.encode!(result))
        end)
      end

      delete "/:id" do
        safe_call(conn, fn ->
          result = handle_delete(id)
          send_resp(conn, 200, Jason.encode!(result))
        end)
      end

      match _ do
        send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      end

    #{indent(handler_code, 2)}
    end
    """
  end

  defp build_template(module_name, handler_code, :webhook) do
    """
    defmodule #{inspect(module_name)} do
      use Plug.Router

      plug :match
      plug Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["*/*"]
      plug :put_json_content_type
      plug :dispatch

      defp put_json_content_type(conn, _opts), do: put_resp_content_type(conn, "application/json")

      post "/" do
        try do
          result = handle_webhook(conn.body_params)
          send_resp(conn, 200, Jason.encode!(result))
        rescue
          e -> send_resp(conn, 500, Jason.encode!(%{error: "handler error", detail: Exception.message(e)}))
        end
      end

      match _ do
        send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      end

    #{indent(handler_code, 2)}
    end
    """
  end

  defp indent(code, spaces) do
    padding = String.duplicate(" ", spaces)

    code
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> padding <> line
    end)
  end
end
