defmodule Blackboex.PageAgent.ContentParserTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.PageAgent.ContentParser

  describe "extract_content/1" do
    test "extracts content between ~~~markdown and ~~~" do
      input = """
      ~~~markdown
      # Hello
      World
      ~~~

      Resumo: feito.
      """

      assert {:ok, "# Hello\nWorld"} = ContentParser.extract_content(input)
    end

    test "accepts ~~~md alias" do
      input = "~~~md\ncontent\n~~~"
      assert {:ok, "content"} = ContentParser.extract_content(input)
    end

    test "accepts ```markdown fence as a fallback" do
      input = "```markdown\nhello\n```"
      assert {:ok, "hello"} = ContentParser.extract_content(input)
    end

    test "accepts plain ~~~ fence without language" do
      input = "~~~\nraw content\n~~~"
      assert {:ok, "raw content"} = ContentParser.extract_content(input)
    end

    test "returns {:error, :no_content_block} when no fence present" do
      assert {:error, :no_content_block} = ContentParser.extract_content("just prose, no fence")
    end

    test "with multiple ~~~ blocks returns the first" do
      input = "~~~markdown\nfirst\n~~~\n\n~~~markdown\nsecond\n~~~"
      assert {:ok, "first"} = ContentParser.extract_content(input)
    end

    test "handles nested backtick code blocks inside ~~~markdown" do
      input = """
      ~~~markdown
      Use this snippet:
      ```elixir
      IO.puts("hi")
      ```
      More text.
      ~~~
      """

      assert {:ok, body} = ContentParser.extract_content(input)
      assert body =~ "```elixir"
      assert body =~ ~s/IO.puts("hi")/
      assert body =~ "More text."
    end

    test "normalizes CRLF to LF" do
      input = "~~~markdown\r\nhello\r\nworld\r\n~~~"
      assert {:ok, "hello\nworld"} = ContentParser.extract_content(input)
    end
  end

  describe "extract_summary/1" do
    test "extracts line starting with 'Resumo:'" do
      input = """
      ~~~markdown
      body
      ~~~

      Resumo: adicionei intro.
      """

      assert ContentParser.extract_summary(input) == "adicionei intro."
    end

    test "returns default when no Resumo line" do
      assert ContentParser.extract_summary("~~~markdown\nx\n~~~") ==
               "Conteúdo atualizado pelo agente"
    end

    test "truncates very long summary to ~200 chars" do
      huge = String.duplicate("a", 500)
      input = "~~~markdown\nx\n~~~\n\nResumo: #{huge}"

      result = ContentParser.extract_summary(input)
      assert String.length(result) <= 205
    end
  end
end
