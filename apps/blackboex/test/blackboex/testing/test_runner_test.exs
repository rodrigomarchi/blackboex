defmodule Blackboex.Testing.TestRunnerTest do
  use ExUnit.Case, async: false

  @moduletag :unit
  @moduletag :capture_log

  alias Blackboex.Testing.TestRunner

  @passing_test_code """
  defmodule BlackboexRunnerTest.Passing do
    use ExUnit.Case, async: false

    test "one plus one" do
      assert 1 + 1 == 2
    end

    test "string concatenation" do
      assert "hello" <> " " <> "world" == "hello world"
    end
  end
  """

  @failing_test_code """
  defmodule BlackboexRunnerTest.Failing do
    use ExUnit.Case, async: false

    test "passes" do
      assert true
    end

    test "fails" do
      assert 1 == 2
    end
  end
  """

  @syntax_error_code """
  defmodule BlackboexRunnerTest.Broken do
    use ExUnit.Case
    test "broken" do
      assert 1 ==
    end
  end
  """

  describe "run/2" do
    test "valid passing tests return results" do
      assert {:ok, results} = TestRunner.run(@passing_test_code)
      assert is_list(results)
      assert length(results) == 2
      assert Enum.all?(results, fn r -> r.status == "passed" end)
    end

    test "failing tests captured in results" do
      assert {:ok, results} = TestRunner.run(@failing_test_code)
      assert length(results) == 2

      passed = Enum.filter(results, fn r -> r.status == "passed" end)
      failed = Enum.filter(results, fn r -> r.status == "failed" end)

      assert length(passed) == 1
      assert length(failed) == 1

      [fail_result] = failed
      assert fail_result.error != nil
    end

    test "syntax error returns compile_error" do
      assert {:error, :compile_error, message} = TestRunner.run(@syntax_error_code)
      assert is_binary(message)
    end

    test "timeout returns error" do
      timeout_code = """
      defmodule BlackboexRunnerTest.Timeout do
        use ExUnit.Case, async: false

        test "hangs forever" do
          Process.sleep(:infinity)
        end
      end
      """

      assert {:error, :timeout} = TestRunner.run(timeout_code, timeout: 500)
    end

    test "results include test names and duration" do
      assert {:ok, results} = TestRunner.run(@passing_test_code)

      for result <- results do
        assert is_binary(result.name)
        assert is_integer(result.duration_ms)
        assert result.duration_ms >= 0
      end
    end

    test "empty module with no tests returns compile error" do
      empty_code = """
      defmodule BlackboexRunnerTest.Empty do
        use ExUnit.Case, async: false
      end
      """

      assert {:error, :compile_error, message} = TestRunner.run(empty_code)
      assert message =~ "No test functions"
    end

    test "error messages are truncated" do
      long_error_code = """
      defmodule BlackboexRunnerTest.LongError do
        use ExUnit.Case, async: false

        test "raises long error" do
          raise String.duplicate("x", 1000)
        end
      end
      """

      assert {:ok, [result]} = TestRunner.run(long_error_code)
      assert result.status == "failed"
      assert byte_size(result.error) <= 503
    end
  end
end
