defmodule Blackboex.LLM.Templates do
  @moduledoc """
  Code generation templates for different API types.
  Each template provides a structural guide for the LLM to follow.
  """

  @spec get(atom()) :: String.t()
  def get(:computation) do
    """
    ## Template: computation (pure function)

    Generate a `def handle(params)` function that receives a map of params and
    returns a result map. The function must be a pure computation — no side effects,
    no database, no external calls.

    IMPORTANT RULES:
    - Define `def handle(params)` that receives a map and returns a map.
    - Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    - Do NOT define a module — only define functions.
    - You may define helper functions with `defp`.
    - Return a plain map like `%{result: value}` — the framework handles JSON encoding.
    - For errors, return `%{error: "message"}`.

    Example:
    ```elixir
    def handle(params) do
      x = Map.get(params, "x", 0)
      y = Map.get(params, "y", 0)
      %{result: x + y, operation: "addition"}
    end
    ```
    """
  end

  def get(:crud) do
    """
    ## Template: CRUD (data operations)

    Generate handler functions for CRUD operations. You MUST define all five functions:

    - `def handle_list(params)` — returns `%{items: [...]}`
    - `def handle_get(id, params)` — returns `%{id: id, ...}`
    - `def handle_create(params)` — returns `%{created: true, data: ...}`
    - `def handle_update(id, params)` — returns `%{id: id, updated: true, ...}`
    - `def handle_delete(id)` — returns `%{id: id, deleted: true}`

    IMPORTANT RULES:
    - Each function receives params (a map) and returns a map.
    - Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    - Do NOT define a module — only define functions.
    - You may define helper functions with `defp`.
    - Return plain maps — the framework handles JSON encoding and HTTP status codes.
    - For errors, return `%{error: "message"}`.

    Example:
    ```elixir
    def handle_list(_params), do: %{items: []}
    def handle_get(id, _params), do: %{id: id, name: "Item"}
    def handle_create(params), do: %{created: true, data: params}
    def handle_update(id, params), do: %{id: id, updated: true, data: params}
    def handle_delete(id), do: %{id: id, deleted: true}
    ```
    """
  end

  def get(:webhook) do
    """
    ## Template: webhook (payload processing)

    Generate a `def handle_webhook(payload)` function that receives and processes
    a webhook payload (decoded JSON as a map). Return an acknowledgment map.

    IMPORTANT RULES:
    - Define `def handle_webhook(payload)` that receives a map and returns a map.
    - Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    - Do NOT define a module — only define functions.
    - You may define helper functions with `defp`.
    - Return a plain map — the framework handles JSON encoding.
    - For errors, return `%{error: "message"}`.

    Example:
    ```elixir
    def handle_webhook(%{"event" => event, "data" => data}) do
      %{status: "received", event: event, processed: true}
    end

    def handle_webhook(_payload) do
      %{error: "invalid payload format"}
    end
    ```
    """
  end
end
