defmodule Blackboex.Playgrounds.ExecutorTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Playgrounds.Executor

  describe "execute/1 basic execution" do
    test "executes simple expression" do
      assert {:ok, "3"} = Executor.execute("1 + 2")
    end

    test "executes multi-line code" do
      code = """
      x = 10
      y = 20
      x + y
      """

      assert {:ok, "30"} = Executor.execute(code)
    end

    test "returns error for syntax errors" do
      assert {:error, _msg} = Executor.execute("def foo(")
    end

    test "returns error for runtime exceptions" do
      assert {:error, _msg} = Executor.execute("raise \"boom\"")
    end

    test "handles timeout" do
      assert {:error, msg} = Executor.execute(":timer.sleep(:infinity)")
      assert msg =~ "timed out" or msg =~ "Execution"
    end
  end

  describe "execute/1 security — blocked modules" do
    test "blocks System module via AST validator" do
      assert {:error, msg} = Executor.execute("System.cmd(\"ls\", [])")
      assert msg =~ "blocked" or msg =~ "not allowed"
    end

    test "blocks File module" do
      assert {:error, msg} = Executor.execute("File.read(\"/etc/hosts\")")
      assert msg =~ "blocked" or msg =~ "not allowed"
    end

    test "blocks Code module" do
      assert {:error, msg} = Executor.execute("Code.eval_string(\"1+1\")")
      assert msg =~ "blocked" or msg =~ "not allowed"
    end
  end

  describe "execute/1 security — sandbox bypass prevention" do
    test "blocks dynamic module construction via atom" do
      code = ~S'mod = :"Elixir.System"; mod.cmd("whoami", [])'
      assert {:error, msg} = Executor.execute(code)
      assert msg =~ "not allowed" or msg =~ "dynamic" or msg =~ "blocked"
    end

    test "blocks Function.capture bypass" do
      code = ~S'Function.capture(:"Elixir.File", :read, 1)'
      assert {:error, msg} = Executor.execute(code)
      assert msg =~ "not allowed" or msg =~ "Function.capture"
    end

    test "blocks defmodule to prevent namespace pollution" do
      code = "defmodule Foo do; def bar, do: :ok; end"
      assert {:error, msg} = Executor.execute(code)
      assert msg =~ "defmodule" or msg =~ "not allowed"
    end

    test "blocks Erlang module calls" do
      code = ":os.cmd(~c\"whoami\")"
      assert {:error, msg} = Executor.execute(code)
      assert msg =~ "not allowed" or msg =~ "blocked" or msg =~ "Erlang"
    end
  end

  describe "execute/1 IO capture" do
    test "captures IO.puts output" do
      code = ~S[IO.puts("hello world")]
      assert {:ok, output} = Executor.execute(code)
      assert output =~ "hello world"
    end

    test "captures IO.puts and returns result" do
      code = """
      IO.puts("side effect")
      1 + 2
      """

      assert {:ok, output} = Executor.execute(code)
      assert output =~ "side effect"
      assert output =~ "3"
    end

    test "captures IO.inspect output" do
      code = ~S[IO.inspect(%{a: 1, b: 2})]
      assert {:ok, output} = Executor.execute(code)
      assert output =~ "a:"
    end
  end

  describe "execute/1 allowed operations" do
    test "allows Enum operations" do
      assert {:ok, "[2, 4, 6]"} = Executor.execute("Enum.map([1,2,3], & &1 * 2)")
    end

    test "allows String operations" do
      assert {:ok, "\"HELLO\""} = Executor.execute("String.upcase(\"hello\")")
    end

    test "allows Map operations" do
      assert {:ok, _} = Executor.execute("Map.put(%{}, :key, :value)")
    end

    test "allows basic arithmetic and data structures" do
      assert {:ok, _} = Executor.execute("[1, 2, 3] |> Enum.sum()")
    end
  end

  describe "execute/3 env bindings" do
    setup do
      {_user, org} = user_and_org_fixture()
      project = Blackboex.Projects.get_default_project(org.id)
      %{org: org, project: project}
    end

    test "env is bound as a map and user code can read values", %{org: org, project: project} do
      project_env_var_fixture(%{
        organization_id: org.id,
        project_id: project.id,
        name: "API_URL",
        value: "https://example.com"
      })

      assert {:ok, ~s("https://example.com")} =
               Executor.execute(~s|env["API_URL"]|, "user-1", project.id)
    end

    test "env lookup of missing key returns nil", %{project: project} do
      assert {:ok, "nil"} =
               Executor.execute(~s|env["MISSING"]|, "user-1", project.id)
    end

    test "no project_id → env binding is an empty map" do
      assert {:ok, "0"} = Executor.execute("map_size(env)", "user-2", nil)
    end

    test "execute/2 (legacy arity) still works — no env loaded" do
      assert {:ok, "0"} = Executor.execute("map_size(env)", "user-3")
    end

    test "env updates are visible to subsequent executions", %{org: org, project: project} do
      var =
        project_env_var_fixture(%{
          organization_id: org.id,
          project_id: project.id,
          name: "DYNAMIC",
          value: "v1"
        })

      assert {:ok, ~s("v1")} =
               Executor.execute(~s|env["DYNAMIC"]|, "user-4", project.id)

      {:ok, _updated} = Blackboex.ProjectEnvVars.update(var, %{value: "v2"})

      assert {:ok, ~s("v2")} =
               Executor.execute(~s|env["DYNAMIC"]|, "user-4", project.id)
    end

    test "security: System.get_env/1 is still blocked regardless of env binding", %{
      project: project
    } do
      assert {:error, msg} =
               Executor.execute(~s|System.get_env("HOME")|, "user-5", project.id)

      assert msg =~ "not allowed" or msg =~ "blocked" or msg =~ "System"
    end
  end
end
