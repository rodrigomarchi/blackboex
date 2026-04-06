defmodule Blackboex.Testing.TestGeneratorTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  import Mox

  alias Blackboex.Apis.Api
  alias Blackboex.Testing.TestGenerator

  setup :verify_on_exit!

  @test_api %Api{
    id: Ecto.UUID.generate(),
    name: "Calculator",
    slug: "calculator",
    description: "A calculator API",
    template_type: "computation",
    method: "POST",
    status: "published",
    visibility: "public",
    requires_auth: false,
    param_schema: %{"number" => "integer"},
    example_request: %{"number" => 42},
    example_response: %{"result" => 84}
  }

  @valid_test_code ~S'''
  ```elixir
  defmodule CalculatorTest do
    use ExUnit.Case, async: true

    @api_url "http://localhost:4000/api/org/calculator"

    test "happy path - doubles number" do
      {:ok, resp} = Req.post(@api_url, json: %{number: 42})
      assert resp.status == 200
      assert resp.body["result"] == 84
    end

    test "handles zero" do
      {:ok, resp} = Req.post(@api_url, json: %{number: 0})
      assert resp.status == 200
      assert resp.body["result"] == 0
    end

    test "handles negative numbers" do
      {:ok, resp} = Req.post(@api_url, json: %{number: -5})
      assert resp.status == 200
      assert resp.body["result"] == -10
    end

    test "invalid input - missing number" do
      {:ok, resp} = Req.post(@api_url, json: %{})
      assert resp.status in [400, 422, 500]
    end

    test "invalid input - string instead of number" do
      {:ok, resp} = Req.post(@api_url, json: %{number: "abc"})
      assert resp.status in [400, 422, 500]
    end
  end
  ```
  '''

  # ── generate_tests/2 ───────────────────────────────────────────

  describe "generate_tests/2" do
    test "returns valid test code on successful generation" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_test_code, usage: %{}}}
      end)

      assert {:ok, %{code: code, usage: _usage}} = TestGenerator.generate_tests(@test_api)
      assert String.contains?(code, "defmodule")
      assert String.contains?(code, "use ExUnit.Case")
      assert String.contains?(code, "test ")
    end

    test "retry on syntax error - succeeds on second attempt" do
      bad_code = """
      ```elixir
      defmodule BrokenTest do
        use ExUnit.Case
        test "broken" do
          assert 1 ==
        end
      end
      ```
      """

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: bad_code, usage: %{}}}
      end)
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_test_code, usage: %{}}}
      end)

      assert {:ok, %{code: code}} = TestGenerator.generate_tests(@test_api)
      assert String.contains?(code, "defmodule")
    end

    test "returns error after max retries exhausted" do
      bad_code = """
      ```elixir
      defmodule BrokenTest do
        use ExUnit.Case
        test "broken" do
          assert 1 ==
        end
      end
      ```
      """

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, 4, fn _prompt, _opts ->
        {:ok, %{content: bad_code, usage: %{}}}
      end)

      assert {:error, :compile_error} = TestGenerator.generate_tests(@test_api)
    end

    test "returns error when LLM fails" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :api_error}
      end)

      assert {:error, :generation_failed} = TestGenerator.generate_tests(@test_api)
    end

    test "returns error when no code block found" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: "Here are some tests but no code block", usage: %{}}}
      end)

      assert {:error, :no_code_found} = TestGenerator.generate_tests(@test_api)
    end

    test "delegates to generate_tests/2 from an Api struct with computation template type" do
      api = %Api{
        id: Ecto.UUID.generate(),
        template_type: "computation",
        name: "SimpleAPI",
        slug: "simple-api",
        description: "Simple computation",
        method: "POST",
        requires_auth: false,
        organization_id: Ecto.UUID.generate(),
        user_id: 0
      }

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_test_code, usage: %{input_tokens: 100, output_tokens: 200}}}
      end)

      assert {:ok, %{code: code, usage: usage}} = TestGenerator.generate_tests(api)
      assert String.contains?(code, "defmodule")
      assert Map.has_key?(usage, :input_tokens) or usage == %{}
    end
  end

  # ── generate_tests_for_code/3 ──────────────────────────────────

  describe "generate_tests_for_code/3 - basic generation" do
    test "returns {:ok, %{code: code}} with valid handler code and compilable LLM response" do
      source = "def handle(%{\"n\" => n}), do: %{result: n * 2}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"returns result\" do\n    assert %{result: _} = Handler.handle(%{})\n  end\nend\n```",
           usage: %{input_tokens: 100, output_tokens: 200}
         }}
      end)

      assert {:ok, %{code: code}} = TestGenerator.generate_tests_for_code(source, "computation")
      assert String.contains?(code, "defmodule HandlerTest")
      assert String.contains?(code, "use ExUnit.Case")
    end

    test "returns usage map alongside code" do
      source = "def handle(p), do: %{result: p}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
           usage: %{input_tokens: 50, output_tokens: 150}
         }}
      end)

      assert {:ok, %{code: _code, usage: usage}} =
               TestGenerator.generate_tests_for_code(source, "computation")

      assert is_map(usage)
    end
  end

  describe "generate_tests_for_code/3 - retry loop" do
    # Code with `assert 1 ==` (incomplete expression) genuinely fails Code.string_to_quoted
    @bad_syntax_code "```elixir\ndefmodule BrokenTest do\n  use ExUnit.Case\n  test \"broken\" do\n    assert 1 ==\n  end\nend\n```"

    test "succeeds on retry when first LLM response has non-compilable code" do
      source = "def handle(p), do: %{result: p}"

      good_code =
        "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @bad_syntax_code, usage: %{}}}
      end)
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: good_code, usage: %{}}}
      end)

      assert {:ok, %{code: code}} =
               TestGenerator.generate_tests_for_code(source, "computation")

      assert String.contains?(code, "defmodule HandlerTest")
    end

    test "returns {:error, :compile_error} when all retries fail" do
      source = "def handle(p), do: %{result: p}"

      # Initial call + 3 retry calls = 4 total
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, 4, fn _prompt, _opts ->
        {:ok, %{content: @bad_syntax_code, usage: %{}}}
      end)

      assert {:error, :compile_error} =
               TestGenerator.generate_tests_for_code(source, "computation")
    end

    test "retry merges usage tokens across LLM calls" do
      source = "def handle(p), do: %{result: p}"

      good_code =
        "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @bad_syntax_code, usage: %{input_tokens: 10, output_tokens: 20}}}
      end)
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: good_code, usage: %{input_tokens: 5, output_tokens: 15}}}
      end)

      assert {:ok, %{usage: usage}} =
               TestGenerator.generate_tests_for_code(source, "computation")

      assert usage.input_tokens == 15
      assert usage.output_tokens == 35
    end
  end

  describe "generate_tests_for_code/3 - LLM failure" do
    test "returns {:error, :generation_failed} when LLM returns error" do
      source = "def handle(p), do: %{result: p}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :generation_failed} =
               TestGenerator.generate_tests_for_code(source, "computation")
    end

    test "returns {:error, :no_code_found} when LLM returns text without code block" do
      source = "def handle(p), do: %{result: p}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: "I cannot generate tests for this code.", usage: %{}}}
      end)

      assert {:error, :no_code_found} =
               TestGenerator.generate_tests_for_code(source, "computation")
    end
  end

  describe "generate_tests_for_code/3 - template types" do
    test "computation template includes Handler.handle in prompt context" do
      test_pid = self()
      source = "def handle(p), do: %{result: p}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn prompt, _opts ->
        send(test_pid, {:prompt, prompt})

        {:ok,
         %{
           content:
             "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, _} = TestGenerator.generate_tests_for_code(source, "computation")
      assert_received {:prompt, prompt}
      assert String.contains?(prompt, "computation")
      assert String.contains?(prompt, "Handler.handle")
    end

    test "crud template type generates tests successfully" do
      source = ~S"""
      def handle_list(_), do: []
      def handle_create(p), do: {:ok, p}
      """

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule CrudTest do\n  use ExUnit.Case\n  test \"list\" do\n    assert [] = Handler.handle_list(%{})\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, %{code: code}} = TestGenerator.generate_tests_for_code(source, "crud")
      assert String.contains?(code, "defmodule CrudTest")
    end

    test "webhook template type generates tests successfully" do
      source = "def handle_webhook(payload), do: {:ok, payload}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule WebhookTest do\n  use ExUnit.Case\n  test \"webhook\" do\n    assert {:ok, _} = Handler.handle_webhook(%{})\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, %{code: code}} = TestGenerator.generate_tests_for_code(source, "webhook")
      assert String.contains?(code, "defmodule WebhookTest")
    end

    test "crud template prompt mentions crud-specific functions" do
      test_pid = self()
      source = "def handle_list(_), do: []"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn prompt, _opts ->
        send(test_pid, {:prompt, prompt})

        {:ok,
         %{
           content:
             "```elixir\ndefmodule CrudTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, _} = TestGenerator.generate_tests_for_code(source, "crud")
      assert_received {:prompt, prompt}
      assert String.contains?(prompt, "handle_list")
    end

    test "webhook template prompt mentions handle_webhook" do
      test_pid = self()
      source = "def handle_webhook(p), do: {:ok, p}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn prompt, _opts ->
        send(test_pid, {:prompt, prompt})

        {:ok,
         %{
           content:
             "```elixir\ndefmodule WebhookTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, _} = TestGenerator.generate_tests_for_code(source, "webhook")
      assert_received {:prompt, prompt}
      assert String.contains?(prompt, "handle_webhook")
    end
  end

  describe "generate_tests_for_code/3 - streaming with token_callback" do
    test "delivers tokens to callback and returns {:ok, result}" do
      test_pid = self()
      source = "def handle(p), do: %{result: p}"

      token1 = "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n"
      token2 = "  test \"ok\" do\n    assert true\n  end\nend\n```"

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:ok, [{:token, token1}, {:token, token2}]}
      end)

      collected = []
      callback = fn token -> send(test_pid, {:token, token}) end

      assert {:ok, %{code: code}} =
               TestGenerator.generate_tests_for_code(source, "computation",
                 token_callback: callback
               )

      assert String.contains?(code, "defmodule HandlerTest")
      assert_received {:token, ^token1}
      assert_received {:token, ^token2}

      _ = collected
    end

    test "returns error when stream_text fails" do
      source = "def handle(p), do: %{result: p}"

      Blackboex.LLM.ClientMock
      |> expect(:stream_text, fn _prompt, _opts ->
        {:error, :stream_failed}
      end)

      assert {:error, :generation_failed} =
               TestGenerator.generate_tests_for_code(source, "computation",
                 token_callback: fn _t -> :ok end
               )
    end
  end

  describe "generate_tests_for_code/3 - edge cases" do
    test "handles empty source code gracefully" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"empty\" do\n    assert true\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, %{code: code}} = TestGenerator.generate_tests_for_code("", "computation")
      assert String.contains?(code, "defmodule")
    end

    test "handles source code with special characters" do
      source = ~S'def handle(%{"key" => val}), do: %{result: "value: #{val}"}'

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"special chars\" do\n    assert true\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, %{code: _code}} =
               TestGenerator.generate_tests_for_code(source, "computation")
    end

    test "accepts opts keyword list for client override" do
      source = "def handle(p), do: %{result: p}"

      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule HandlerTest do\n  use ExUnit.Case\n  test \"ok\" do\n    assert true\n  end\nend\n```",
           usage: %{}
         }}
      end)

      assert {:ok, %{code: _code}} =
               TestGenerator.generate_tests_for_code(source, "computation",
                 client: Blackboex.LLM.ClientMock
               )
    end
  end
end
