defmodule Blackboex.LLM.Templates do
  @moduledoc """
  Code generation templates for different API types.
  Each template provides a structural guide for the LLM to follow.
  """

  @spec get(atom()) :: String.t()
  def get(:computation) do
    """
    ## Template: computation (pure function)

    Generate the body of a handler function that receives `params` (a map) and
    returns a result map. The function should be a pure computation — no side effects,
    no database, no external calls.

    The handler receives `conn` and `params`, processes the params, and returns
    a JSON response via `json(conn, result)`.

    Example structure:
    ```elixir
    def call(conn, params) do
      # Extract and validate params
      # Perform computation
      # Return json(conn, %{result: ...})
    end
    ```
    """
  end

  def get(:crud) do
    """
    ## Template: CRUD (data operations)

    Generate the body of a handler function that performs CRUD operations.
    The handler should support create, read, list, update, and delete operations
    using only maps and lists for in-memory data manipulation.
    Do NOT use Agent, GenServer, ETS, or any process-based storage.

    The handler receives `conn` and `params`, and should route based on the
    `action` parameter. Return JSON responses via `json(conn, result)`.

    Example structure:
    ```elixir
    def call(conn, %{"action" => "create", "data" => data}) do
      # Validate data using Map and String functions
      # Return json(conn, %{status: "created", data: data})
    end

    def call(conn, %{"action" => "list"}) do
      # Return json(conn, %{items: []})
    end
    ```
    """
  end

  def get(:webhook) do
    """
    ## Template: webhook (payload processing)

    Generate the body of a handler function that receives and processes a webhook payload.
    The handler should validate the incoming payload structure, extract relevant data,
    and return an acknowledgment response.

    The handler receives `conn` and `params` (the decoded JSON payload).
    Return a JSON response via `json(conn, result)`.

    Example structure:
    ```elixir
    def call(conn, %{"event" => event, "payload" => payload}) do
      # Validate event type
      # Process payload
      # Return json(conn, %{status: "received", event: event})
    end
    ```
    """
  end
end
