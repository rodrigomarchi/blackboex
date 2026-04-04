defmodule Blackboex.CodeGen.ASTValidatorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.CodeGen.ASTValidator

  describe "validate/1 with safe code" do
    test "accepts code using allowed modules (Enum, Map, String, List, Jason)" do
      code = """
      defmodule MyApi do
        def handle(params) do
          params
          |> Map.get("items", [])
          |> Enum.map(&String.upcase/1)
          |> List.flatten()
          |> Jason.encode!()
        end
      end
      """

      assert {:ok, _ast} = ASTValidator.validate(code)
    end

    test "accepts code using Keyword, Tuple, MapSet" do
      code = """
      defmodule MyApi do
        def handle(params) do
          opts = Keyword.merge([a: 1], [b: 2])
          set = MapSet.new([1, 2, 3])
          Tuple.to_list({opts, set})
        end
      end
      """

      assert {:ok, _ast} = ASTValidator.validate(code)
    end

    test "accepts code using Date, Time, DateTime, NaiveDateTime" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          now = DateTime.utc_now()
          date = Date.utc_today()
          time = Time.utc_now()
          naive = NaiveDateTime.utc_now()
          {now, date, time, naive}
        end
      end
      """

      assert {:ok, _ast} = ASTValidator.validate(code)
    end

    test "accepts code using Regex, URI, Access" do
      code = """
      defmodule MyApi do
        def handle(params) do
          uri = URI.parse("https://example.com")
          match = Regex.match?(~r/hello/, "hello world")
          val = Access.get(params, "key")
          {uri, match, val}
        end
      end
      """

      assert {:ok, _ast} = ASTValidator.validate(code)
    end

    test "accepts code using Integer, Float" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Integer.to_string(42) <> " " <> Float.to_string(3.14)
        end
      end
      """

      assert {:ok, _ast} = ASTValidator.validate(code)
    end

    test "accepts pure functional code without module references" do
      code = """
      defmodule MyApi do
        def handle(params) do
          x = params["a"] + params["b"]
          %{result: x * 2}
        end
      end
      """

      assert {:ok, _ast} = ASTValidator.validate(code)
    end
  end

  describe "validate/1 rejects dangerous code" do
    test "rejects File.read" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          File.read("/etc/passwd")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "File"))
    end

    test "rejects System.cmd" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          System.cmd("ls", ["/"])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "System"))
    end

    test "rejects :os.cmd" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          :os.cmd(~c"ls /")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, ":os"))
    end

    test "rejects :erlang.open_port" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          :erlang.open_port({:spawn, "ls"}, [])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, ":erlang"))
    end

    test "rejects Process.spawn" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Process.spawn(fn -> :ok end, [])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Process"))
    end

    test "rejects Code.eval_string" do
      code = """
      defmodule MyApi do
        def handle(params) do
          Code.eval_string(params["code"])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Code"))
    end

    test "rejects send/2" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          send(self(), :hello)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "send"))
    end

    test "rejects receive block" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          receive do
            msg -> msg
          end
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "receive"))
    end

    test "rejects import of dangerous module" do
      code = """
      defmodule MyApi do
        import File
        def handle(_params) do
          read("/etc/passwd")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "File"))
    end

    test "rejects apply/3 with dynamic module" do
      code = """
      defmodule MyApi do
        def handle(params) do
          mod = params["module"]
          apply(mod, :run, [])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "apply"))
    end

    test "rejects IO module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          IO.puts("hello")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "IO"))
    end

    test "rejects Module module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Module.create(Foo, quote(do: def(x, do: x)), __ENV__)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Module"))
    end

    test "rejects Node module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Node.list()
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Node"))
    end

    test "rejects Application module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Application.get_all_env(:blackboex)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Application"))
    end

    test "rejects :ets module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          :ets.new(:my_table, [:set])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, ":ets"))
    end

    test "rejects :gen_tcp module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          :gen_tcp.connect(~c"localhost", 80, [])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, ":gen_tcp"))
    end

    test "rejects Port module" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Port.open({:spawn, "ls"}, [])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Port"))
    end
  end

  describe "validate/1 collects multiple violations" do
    test "returns all violations, not just the first" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          File.read("/etc/passwd")
          System.cmd("ls", ["/"])
          :os.cmd(~c"ls")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert length(reasons) >= 3
    end
  end

  describe "validate/1 handles parse errors" do
    test "returns error for syntax errors" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          %{missing_closing_brace
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "parse"))
    end
  end

  describe "validate/1 blocks Kernel function bypasses" do
    test "rejects spawn/1" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          spawn(fn -> :ok end)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "spawn"))
    end

    test "rejects spawn_link/1" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          spawn_link(fn -> :ok end)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "spawn_link"))
    end

    test "rejects exit/1" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          exit(:kill)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "exit"))
    end

    test "rejects throw/1" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          throw(:escape)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "throw"))
    end

    test "rejects Kernel.send/2 (module-qualified bypass)" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Kernel.send(self(), :hello)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "send"))
    end

    test "rejects Kernel.apply/3 (module-qualified bypass)" do
      code = """
      defmodule MyApi do
        def handle(params) do
          Kernel.apply(params["mod"], :run, [])
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "apply"))
    end

    test "rejects Kernel.spawn/1 (module-qualified bypass)" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          Kernel.spawn(fn -> :ok end)
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "spawn"))
    end
  end

  describe "validate/1 blocks runtime module construction bypass" do
    test "rejects String.to_atom (can construct dangerous module atoms)" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          mod = String.to_atom("Elixir.File")
          mod.read("/etc/passwd")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "String.to_atom"))
    end

    test "rejects String.to_existing_atom" do
      code = """
      defmodule MyApi do
        def handle(_params) do
          String.to_existing_atom("Elixir.System")
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "String.to_existing_atom"))
    end
  end

  describe "validate/1 blocks require of dangerous modules" do
    test "rejects require Code" do
      code = """
      defmodule MyApi do
        require Code
        def handle(_params), do: :ok
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "Code"))
    end
  end

  describe "validate/1 atom table protection" do
    test "rejects code with excessive unknown atoms" do
      # Generate code with many unique atoms to exhaust atom table (limit: 1000)
      atoms =
        1..1100
        |> Enum.map(fn i -> ":unique_atom_#{i}_#{:rand.uniform(999_999)}" end)
        |> Enum.join(", ")

      code = """
      defmodule MyApi do
        def handle(_params) do
          [#{atoms}]
        end
      end
      """

      assert {:error, reasons} = ASTValidator.validate(code)
      assert Enum.any?(reasons, &String.contains?(&1, "atom"))
    end
  end
end
