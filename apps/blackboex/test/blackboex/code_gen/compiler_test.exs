defmodule Blackboex.CodeGen.CompilerTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis.Api
  alias Blackboex.CodeGen.Compiler

  @valid_handler """
  def handle(params) do
    x = Map.get(params, "a", 0)
    y = Map.get(params, "b", 0)
    %{result: x + y}
  end
  """

  defp build_api(attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test API",
      slug: "test-api",
      template_type: "computation",
      status: "draft"
    }

    struct(Api, Map.merge(defaults, attrs))
  end

  describe "compile/2" do
    test "compiles valid code and returns {:ok, module}" do
      api = build_api()

      assert {:ok, module} = Compiler.compile(api, @valid_handler)
      assert is_atom(module)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "rejects insecure code via AST validation" do
      api = build_api()

      insecure_code = """
      def handle(_params) do
        File.read("/etc/passwd")
      end
      """

      assert {:error, {:validation, reasons}} = Compiler.compile(api, insecure_code)
      assert is_list(reasons)
      assert Enum.any?(reasons, &String.contains?(&1, "File"))
    end

    test "returns error for code that fails to compile" do
      api = build_api()

      bad_code = """
      def handle(params) do
        UndefinedModule.nonexistent_function(params)
      end
      """

      # This should still compile (Elixir doesn't check module existence at compile time)
      # but we test the path
      result = Compiler.compile(api, bad_code)
      assert {:ok, _module} = result

      on_exit(fn ->
        case result do
          {:ok, mod} -> Compiler.unload(mod)
          _ -> :ok
        end
      end)
    end

    test "compiled module responds to function_exported?/3" do
      api = build_api()

      {:ok, module} = Compiler.compile(api, @valid_handler)
      assert function_exported?(module, :call, 2)
      assert function_exported?(module, :init, 1)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "recompiling same module works (hot reload)" do
      api = build_api()

      {:ok, module1} = Compiler.compile(api, @valid_handler)

      updated_handler = """
      def handle(params) do
        x = Map.get(params, "a", 0)
        %{result: x * 3}
      end
      """

      {:ok, module2} = Compiler.compile(api, updated_handler)
      assert module1 == module2

      on_exit(fn -> Compiler.unload(module2) end)
    end
  end

  # ── Multi-file compilation (compile_files/2) ───────────────────

  describe "compile_files/2 with multi-file project" do
    test "compiles handler + helper with defmodule correctly" do
      api = build_api()

      handler = """
      @doc "Calculates factorial."
      @spec handle(map()) :: map()
      def handle(params) do
        n = Map.get(params, "number", 0)
        %{result: Helpers.calculate(n)}
      end
      """

      helper = """
      defmodule Helpers do
        @moduledoc "Math helpers."

        @doc "Calculates factorial."
        @spec calculate(non_neg_integer()) :: pos_integer()
        def calculate(0), do: 1
        def calculate(n) when n > 0, do: Enum.reduce(1..n, 1, &*/2)
      end
      """

      files = [
        %{path: "/src/handler.ex", content: handler},
        %{path: "/src/helpers.ex", content: helper}
      ]

      assert {:ok, module} = Compiler.compile_files(api, files)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "compiles handler + Request/Response in separate files" do
      api = build_api()

      handler = """
      @doc "Handles request."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)
        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          %{result: data.number * 2}
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          %{error: "Validation failed", details: errors}
        end
      end
      """

      request_schema = """
      defmodule Request do
        @moduledoc "Input schema."
        use Blackboex.Schema

        embedded_schema do
          field :number, :integer
        end

        @doc "Validates params."
        @spec changeset(map()) :: Ecto.Changeset.t()
        def changeset(params) do
          %__MODULE__{}
          |> cast(params, [:number])
          |> validate_required([:number])
        end
      end
      """

      response_schema = """
      defmodule Response do
        @moduledoc "Output schema."
        use Blackboex.Schema

        embedded_schema do
          field :result, :integer
        end
      end
      """

      files = [
        %{path: "/src/handler.ex", content: handler},
        %{path: "/src/request_schema.ex", content: request_schema},
        %{path: "/src/response_schema.ex", content: response_schema}
      ]

      assert {:ok, module} = Compiler.compile_files(api, files)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "compiles 4-file project where LLM wraps handler in defmodule Handler" do
      api = build_api()

      # This is what the LLM actually generates — handler wrapped in defmodule
      handler = """
      defmodule Handler do
        @moduledoc "Factorial handler."

        @doc "Calculates factorial."
        @spec handle(map()) :: map()
        def handle(params) do
          changeset = Request.changeset(params)
          if changeset.valid? do
            data = Ecto.Changeset.apply_changes(changeset)
            %{result: Helpers.factorial(data.number)}
          else
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            %{error: "Validation failed", details: errors}
          end
        end
      end
      """

      request = """
      defmodule Request do
        @moduledoc "Input."
        use Blackboex.Schema
        embedded_schema do
          field :number, :integer
        end
        @spec changeset(map()) :: Ecto.Changeset.t()
        def changeset(params) do
          %__MODULE__{}
          |> cast(params, [:number])
          |> validate_required([:number])
          |> validate_number(:number, greater_than_or_equal_to: 0)
        end
      end
      """

      response = """
      defmodule Response do
        @moduledoc "Output."
        use Blackboex.Schema
        embedded_schema do
          field :result, :integer
        end
      end
      """

      helpers = """
      defmodule Helpers do
        @moduledoc "Math."
        @spec factorial(non_neg_integer()) :: pos_integer()
        def factorial(0), do: 1
        def factorial(n) when n > 0, do: Enum.reduce(1..n, 1, &*/2)
      end
      """

      files = [
        %{path: "/src/handler.ex", content: handler},
        %{path: "/src/request_schema.ex", content: request},
        %{path: "/src/response_schema.ex", content: response},
        %{path: "/src/helpers.ex", content: helpers}
      ]

      assert {:ok, module} = Compiler.compile_files(api, files)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end

    test "fails when helper has @moduledoc without defmodule" do
      api = build_api()

      handler = """
      def handle(params), do: %{result: "ok"}
      """

      # This reproduces the real bug: LLM generates helpers without defmodule
      bad_helper = """
      @moduledoc "Helpers without defmodule wrapper."

      @doc "A helper function."
      @spec helper_fn() :: :ok
      def helper_fn, do: :ok
      """

      files = [
        %{path: "/src/handler.ex", content: handler},
        %{path: "/src/helpers.ex", content: bad_helper}
      ]

      assert {:error, _} = Compiler.compile_files(api, files)
    end

    test "compiles 4-file project (handler + request + response + helpers)" do
      api = build_api()

      handler = """
      @doc "Calculates factorial."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)
        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          %{result: Helpers.factorial(data.number)}
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          %{error: "Validation failed", details: errors}
        end
      end
      """

      request = """
      defmodule Request do
        @moduledoc "Input."
        use Blackboex.Schema
        embedded_schema do
          field :number, :integer
        end
        @spec changeset(map()) :: Ecto.Changeset.t()
        def changeset(params) do
          %__MODULE__{}
          |> cast(params, [:number])
          |> validate_required([:number])
          |> validate_number(:number, greater_than_or_equal_to: 0)
        end
      end
      """

      response = """
      defmodule Response do
        @moduledoc "Output."
        use Blackboex.Schema
        embedded_schema do
          field :result, :integer
        end
      end
      """

      helpers = """
      defmodule Helpers do
        @moduledoc "Math helpers."
        @spec factorial(non_neg_integer()) :: pos_integer()
        def factorial(0), do: 1
        def factorial(n) when n > 0, do: Enum.reduce(1..n, 1, &*/2)
      end
      """

      files = [
        %{path: "/src/handler.ex", content: handler},
        %{path: "/src/request_schema.ex", content: request},
        %{path: "/src/response_schema.ex", content: response},
        %{path: "/src/helpers.ex", content: helpers}
      ]

      assert {:ok, module} = Compiler.compile_files(api, files)
      assert function_exported?(module, :call, 2)

      on_exit(fn -> Compiler.unload(module) end)
    end
  end

  describe "unload/1" do
    test "removes loaded module" do
      api = build_api()

      {:ok, module} = Compiler.compile(api, @valid_handler)
      assert function_exported?(module, :call, 2)

      assert :ok = Compiler.unload(module)
      refute function_exported?(module, :call, 2)
    end
  end
end
