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
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        %{error: "Validation failed", details: errors}
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
    - Every public `def` MUST have @doc and @spec directly above it.

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

    @doc "Lists all items, optionally filtered by params."
    @spec handle_list(map()) :: map()
    def handle_list(_params), do: %{items: []}

    @doc "Returns a single item by ID."
    @spec handle_get(String.t(), map()) :: map()
    def handle_get(id, _params), do: %{id: id, name: "Item"}

    @doc "Creates a new item after validating input."
    @spec handle_create(map()) :: map()
    def handle_create(params) do
      changeset = Request.changeset(params)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        %{created: true, data: Map.from_struct(data)}
      else
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        %{error: "Validation failed", details: errors}
      end
    end

    @doc "Updates an existing item by ID."
    @spec handle_update(String.t(), map()) :: map()
    def handle_update(id, params) do
      changeset = Request.changeset(params)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        %{id: id, updated: true, data: Map.from_struct(data)}
      else
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        %{error: "Validation failed", details: errors}
      end
    end

    @doc "Deletes an item by ID."
    @spec handle_delete(String.t()) :: map()
    def handle_delete(id), do: %{id: id, deleted: true}
    ```

    REMEMBER: Every `def` MUST have @doc and @spec directly above it. Max 40 lines per function. Max 120 chars per line.
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

  @doc "Guide for multi-file project structure — shown to LLM during planning and generation."
  @spec get_multi_file_guide() :: String.t()
  def get_multi_file_guide do
    """
    ## Multi-File Project Structure

    When an API is complex enough, code can be organized into multiple files:

    ### Example: Currency Converter API

    **File: /src/handler.ex** (entry point)
    ```elixir
    @moduledoc "Main handler for currency conversion API."

    defmodule Response do
      @moduledoc "Response schema for conversion results."
      use Blackboex.Schema

      embedded_schema do
        field :from, :string
        field :to, :string
        field :amount, :float
        field :result, :float
        field :rate, :float
      end
    end

    @doc "Converts an amount between currencies."
    @spec handle(map()) :: map()
    def handle(params) do
      changeset = Request.changeset(params)

      if changeset.valid? do
        data = Ecto.Changeset.apply_changes(changeset)
        rate = Rates.get_rate(data.from, data.to)
        result = data.amount * rate
        %{from: data.from, to: data.to, amount: data.amount, result: Float.round(result, 2), rate: rate}
      else
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        %{error: "Validation failed", details: errors}
      end
    end
    ```

    **File: /src/request.ex** (input validation)
    ```elixir
    defmodule Request do
      @moduledoc "Input schema for currency conversion. Validates from/to currency codes and amount."
      use Blackboex.Schema

      @supported_currencies ~w(USD EUR GBP BRL JPY CAD AUD CHF)

      embedded_schema do
        field :from, :string
        field :to, :string
        field :amount, :float
      end

      @doc "Validates conversion parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:from, :to, :amount])
        |> validate_required([:from, :to, :amount])
        |> validate_inclusion(:from, @supported_currencies)
        |> validate_inclusion(:to, @supported_currencies)
        |> validate_number(:amount, greater_than: 0)
      end
    end
    ```

    **File: /src/rates.ex** (helper module)
    ```elixir
    defmodule Rates do
      @moduledoc "Exchange rate lookup. Provides hardcoded rates for supported currency pairs."

      @rates %{
        {"USD", "EUR"} => 0.92, {"EUR", "USD"} => 1.09,
        {"USD", "GBP"} => 0.79, {"GBP", "USD"} => 1.27,
        {"USD", "BRL"} => 4.97, {"BRL", "USD"} => 0.20
      }

      @doc "Returns the exchange rate for a currency pair."
      @spec get_rate(String.t(), String.t()) :: float()
      def get_rate(from, to) when from == to, do: 1.0
      def get_rate(from, to), do: Map.get(@rates, {from, to}, 1.0)
    end
    ```

    ### Guidelines for Multi-File
    - `/src/handler.ex` is ALWAYS the entry point — it contains `handle/1` (or CRUD handlers)
    - Helper modules are referenced by their module name directly (e.g., `Rates.get_rate/2`)
    - Each file should have a single responsibility
    - Keep files under 80 lines
    - `Request` and `Response` schemas can live in handler.ex or in separate files
    """
  end
end
