defmodule Blackboex.FlowExecutor.Nodes.ElixirCodeTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.FlowExecutor.Nodes.ElixirCode

  describe "run/3" do
    test "evaluates code with input binding" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [code: "String.upcase(input)"]

      assert {:ok, %{output: "HELLO", state: %{}}} = ElixirCode.run(args, %{}, opts)
    end

    test "evaluates code with state binding" do
      args = %{prev_result: %{output: "world", state: %{"greeting" => "hello"}}}
      opts = [code: ~s|state["greeting"] <> " " <> input|]

      assert {:ok, %{output: "hello world", state: %{"greeting" => "hello"}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "handles {output, new_state} tuple return" do
      args = %{prev_result: %{output: 5, state: %{"count" => 10}}}
      opts = [code: ~s|{input * 2, Map.put(state, "count", state["count"] + input)}|]

      assert {:ok, %{output: 10, state: %{"count" => 15}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "plain value return keeps state unchanged" do
      args = %{prev_result: %{output: "data", state: %{"key" => "value"}}}
      opts = [code: "String.length(input)"]

      assert {:ok, %{output: 4, state: %{"key" => "value"}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "returns error on runtime exception" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [code: "String.to_integer(input)"]

      assert {:error, _reason} = ElixirCode.run(args, %{}, opts)
    end

    test "returns error on syntax error" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [code: "def foo do end end"]

      assert {:error, _reason} = ElixirCode.run(args, %{}, opts)
    end

    test "times out on long-running code" do
      args = %{prev_result: %{output: 1, state: %{}}}
      opts = [code: ":timer.sleep(5000); input", timeout_ms: 50]

      assert {:error, "execution timed out after" <> _} = ElixirCode.run(args, %{}, opts)
    end

    test "falls back to input key when prev_result not present" do
      args = %{input: "test"}
      opts = [code: "state"]

      assert {:ok, %{output: %{}, state: %{}}} = ElixirCode.run(args, %{}, opts)
    end

    test "exposes env bindings from context" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|env["FOO"]|]
      context = %{env: %{"FOO" => "bar"}}

      assert {:ok, %{output: "bar", state: %{}}} = ElixirCode.run(args, context, opts)
    end

    test "env lookup of missing key returns nil (not raise)" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|env["MISSING"]|]
      context = %{env: %{"FOO" => "bar"}}

      assert {:ok, %{output: nil, state: %{}}} = ElixirCode.run(args, context, opts)
    end

    test "env defaults to empty map when context has no :env" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: "map_size(env)"]

      assert {:ok, %{output: 0, state: %{}}} = ElixirCode.run(args, %{}, opts)
    end

    test "env binding does not overwrite input or state" do
      args = %{prev_result: %{output: %{"k" => "v"}, state: %{"s" => 1}}}
      opts = [code: ~s|{input["k"], Map.put(state, "env_ok", map_size(env) >= 0)}|]
      context = %{env: %{"X" => "y"}}

      assert {:ok, %{output: "v", state: %{"s" => 1, "env_ok" => true}}} =
               ElixirCode.run(args, context, opts)
    end

    test "env is a map, not keyword — atom keys do not match string keys" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|env[:foo]|]
      context = %{env: %{"foo" => "bar"}}

      # Map.get(%{"foo" => "bar"}, :foo) returns nil — no automatic atom→string
      assert {:ok, %{output: nil, state: %{}}} = ElixirCode.run(args, context, opts)
    end
  end

  describe "run/3 security — AST validation" do
    test "rejects File.read/1" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|File.read!("/etc/passwd")|]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "rejects System.get_env/1" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|System.get_env("HOME")|]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "rejects :os.cmd/1 via Erlang module call" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|:os.cmd(~c"whoami")|]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "rejects Code.eval_string (nested eval)" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|Code.eval_string("1 + 1")|]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "rejects apply(:erlang, :system_flag, ...)" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|apply(:erlang, :system_flag, [:schedulers_online, 1])|]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "rejects Application.get_env" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: ~s|Application.get_env(:blackboex, :secret)|]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "rejects syntax errors with security_violation tag (via validator)" do
      args = %{prev_result: %{output: "x", state: %{}}}
      opts = [code: "def foo do end end"]

      assert {:error, {:security_violation, _reasons}} = ElixirCode.run(args, %{}, opts)
    end

    test "allows Enum operations" do
      args = %{prev_result: %{output: [1, 2, 3], state: %{}}}
      opts = [code: "Enum.sum(input)"]

      assert {:ok, %{output: 6, state: %{}}} = ElixirCode.run(args, %{}, opts)
    end

    test "allows Map operations" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [code: ~s|Map.put(%{}, "greeting", input)|]

      assert {:ok, %{output: %{"greeting" => "hello"}, state: %{}}} =
               ElixirCode.run(args, %{}, opts)
    end

    test "allows String operations" do
      args = %{prev_result: %{output: "hello", state: %{}}}
      opts = [code: "String.upcase(input)"]

      assert {:ok, %{output: "HELLO", state: %{}}} = ElixirCode.run(args, %{}, opts)
    end
  end

  describe "run/3 stack-trace sanitization" do
    test "redacts env values from error messages" do
      args = %{prev_result: %{output: "x", state: %{}}}
      # Runtime error that references env value in the message
      opts = [
        code: ~s|raise env["SECRET_TOKEN"]|
      ]

      context = %{env: %{"SECRET_TOKEN" => "super-secret-abc-12345"}}

      assert {:error, msg} = ElixirCode.run(args, context, opts)
      refute msg =~ "super-secret-abc-12345"
      assert msg =~ "{{env.SECRET_TOKEN}}"
    end
  end

  describe "undo/4" do
    test "returns :ok when no undo_code provided" do
      value = %{output: "result", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}

      assert :ok = ElixirCode.undo(value, args, %{}, [])
    end

    test "executes undo_code with result binding" do
      value = %{output: "created_thing", state: %{}}
      args = %{prev_result: %{output: "input", state: %{"id" => "123"}}}
      opts = [undo_code: ~s|{input, state["id"], result}|, timeout_ms: 5_000]

      assert :ok = ElixirCode.undo(value, args, %{}, opts)
    end

    test "swallows errors in undo_code (best-effort)" do
      value = %{output: "x", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}
      opts = [undo_code: ~s|raise "undo failed"|, timeout_ms: 5_000]

      assert :ok = ElixirCode.undo(value, args, %{}, opts)
    end

    test "returns :ok for empty undo_code" do
      value = %{output: "x", state: %{}}
      args = %{prev_result: %{output: "input", state: %{}}}

      assert :ok = ElixirCode.undo(value, args, %{}, undo_code: "")
    end
  end
end
