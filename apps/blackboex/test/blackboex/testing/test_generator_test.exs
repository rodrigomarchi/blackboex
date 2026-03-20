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
    example_response: %{"result" => 84},
    source_code: ~S"""
    def handle(%{"number" => n}) do
      %{result: n * 2}
    end
    """
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

  describe "generate_tests/2" do
    test "returns valid test code on successful generation" do
      Blackboex.LLM.ClientMock
      |> expect(:generate_text, fn _prompt, _opts ->
        {:ok, %{content: @valid_test_code, usage: %{}}}
      end)

      assert {:ok, code} = TestGenerator.generate_tests(@test_api)
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

      assert {:ok, code} = TestGenerator.generate_tests(@test_api)
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
  end
end
