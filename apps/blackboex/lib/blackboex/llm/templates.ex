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
    - Define `defmodule Request` and `defmodule Response` with `use Blackboex.Schema`.
    - Define `def handle(params)` that receives a map and returns a map.
    - The handler MUST use `Request.changeset(params)` to validate input.
    - Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    - You may define helper functions with `defp`.
    - Return a plain map like `%{result: value}` — the framework handles JSON encoding.
    - For errors, return `%{error: "message"}`.

    Example:
    ```elixir
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :x, :integer
        field :y, :integer
      end

      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:x, :y])
        |> validate_required([:x, :y])
      end
    end

    defmodule Response do
      use Blackboex.Schema

      embedded_schema do
        field :result, :integer
        field :operation, :string
      end
    end

    @doc "Adds two numbers."
    @spec handle(map()) :: map()
    def handle(params) do
      changeset = Request.changeset(params)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        %{result: data.x + data.y, operation: "addition"}
      else
        %{error: "Invalid input"}
      end
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
    - Define `defmodule Request` and `defmodule Response` with `use Blackboex.Schema`.
    - Each function receives params (a map) and returns a map.
    - Create and update handlers MUST use `Request.changeset(params)` to validate input.
    - Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    - You may define helper functions with `defp`.
    - Return plain maps — the framework handles JSON encoding and HTTP status codes.
    - For errors, return `%{error: "message"}`.

    Example:
    ```elixir
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :name, :string
        field :email, :string
      end

      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:name, :email])
        |> validate_required([:name, :email])
      end
    end

    defmodule Response do
      use Blackboex.Schema

      embedded_schema do
        field :id, :string
        field :name, :string
        field :email, :string
      end
    end

    def handle_list(_params), do: %{items: []}
    def handle_get(id, _params), do: %{id: id, name: "Item"}

    def handle_create(params) do
      changeset = Request.changeset(params)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        %{created: true, data: Map.from_struct(data)}
      else
        %{error: "Invalid input"}
      end
    end

    def handle_update(id, params) do
      changeset = Request.changeset(params)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        %{id: id, updated: true, data: Map.from_struct(data)}
      else
        %{error: "Invalid input"}
      end
    end

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
    - Define `defmodule Request` and `defmodule Response` with `use Blackboex.Schema`.
    - Define `def handle_webhook(payload)` that receives a map and returns a map.
    - The handler MUST use `Request.changeset(payload)` to validate the payload.
    - Do NOT use `conn`, `json/2`, `put_status/2`, or any Plug/Phoenix functions.
    - You may define helper functions with `defp`.
    - Return a plain map — the framework handles JSON encoding.
    - For errors, return `%{error: "message"}`.

    Example:
    ```elixir
    defmodule Request do
      use Blackboex.Schema

      embedded_schema do
        field :event, :string
        field :data, :map
      end

      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:event, :data])
        |> validate_required([:event])
      end
    end

    defmodule Response do
      use Blackboex.Schema

      embedded_schema do
        field :status, :string
        field :event, :string
        field :processed, :boolean
      end
    end

    @doc "Processes incoming webhook payload."
    @spec handle_webhook(map()) :: map()
    def handle_webhook(payload) do
      changeset = Request.changeset(payload)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        %{status: "received", event: data.event, processed: true}
      else
        %{error: "invalid payload format"}
      end
    end
    ```
    """
  end
end
