defmodule Blackboex.PlaygroundAgent.CodeParserTest do
  use ExUnit.Case, async: true

  alias Blackboex.PlaygroundAgent.CodeParser

  describe "extract_code/1" do
    test "extracts code from an ```elixir fence" do
      content = """
      Aqui está:
      ```elixir
      IO.puts("oi")
      ```
      Resumo: prints oi
      """

      assert {:ok, "IO.puts(\"oi\")"} = CodeParser.extract_code(content)
    end

    test "also accepts ```ex fence" do
      content = "```ex\nx = 1\n```"
      assert {:ok, "x = 1"} = CodeParser.extract_code(content)
    end

    test "falls back to generic fence when no language specified" do
      content = "```\nIO.puts(:ok)\n```"
      assert {:ok, "IO.puts(:ok)"} = CodeParser.extract_code(content)
    end

    test "returns error when no fence is present" do
      assert {:error, :no_code_block} = CodeParser.extract_code("só prosa, sem código")
    end

    test "returns the first fence when multiple are present" do
      content = """
      ```elixir
      primeiro
      ```
      e mais:
      ```elixir
      segundo
      ```
      """

      assert {:ok, "primeiro"} = CodeParser.extract_code(content)
    end
  end

  describe "extract_summary/1" do
    test "picks up a Resumo: line" do
      content = "```elixir\nx\n```\nResumo: soma dois números"
      assert "soma dois números" = CodeParser.extract_summary(content)
    end

    test "defaults when no summary is present" do
      assert "Código gerado pelo agente" = CodeParser.extract_summary("```elixir\nx\n```")
    end
  end
end
