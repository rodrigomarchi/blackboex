defmodule Blackboex.FlowAgent.DefinitionParserTest do
  use ExUnit.Case, async: true

  alias Blackboex.FlowAgent.DefinitionParser

  @minimal_definition %{
    "version" => "1.0",
    "nodes" => [
      %{"id" => "n1", "type" => "start", "position" => %{"x" => 0, "y" => 0}, "data" => %{}}
    ],
    "edges" => []
  }

  describe "extract_definition/1" do
    test "returns {:ok, map} when ~~~json fence is present" do
      body = """
      I will build the flow:

      ~~~json
      #{Jason.encode!(@minimal_definition)}
      ~~~

      Summary: basic flow
      """

      assert {:ok, parsed} = DefinitionParser.extract_definition(body)
      assert parsed["version"] == "1.0"
      assert [%{"id" => "n1"}] = parsed["nodes"]
    end

    test "falls back to ~~~ without language tag" do
      body = "~~~\n#{Jason.encode!(@minimal_definition)}\n~~~"
      assert {:ok, parsed} = DefinitionParser.extract_definition(body)
      assert parsed["version"] == "1.0"
    end

    test "falls back to ```json (backticks) as last resort" do
      body = "```json\n#{Jason.encode!(@minimal_definition)}\n```"
      assert {:ok, parsed} = DefinitionParser.extract_definition(body)
      assert parsed["version"] == "1.0"
    end

    test "returns {:error, :no_json_block} when no fence present" do
      assert {:error, :no_json_block} = DefinitionParser.extract_definition("just prose")
    end

    test "returns {:error, {:invalid_json, _}} when JSON malformed" do
      body = "~~~json\n{not valid json\n~~~"
      assert {:error, {:invalid_json, _reason}} = DefinitionParser.extract_definition(body)
    end

    test "ignores prose before and after the fence" do
      body = """
      Here is the requested flow:

      ~~~json
      #{Jason.encode!(@minimal_definition)}
      ~~~

      Summary: ready.
      Any other line.
      """

      assert {:ok, parsed} = DefinitionParser.extract_definition(body)
      assert parsed["version"] == "1.0"
    end

    test "handles multiline JSON with embedded newlines inside strings" do
      definition = %{
        "version" => "1.0",
        "nodes" => [
          %{
            "id" => "n1",
            "type" => "elixir_code",
            "position" => %{"x" => 0, "y" => 0},
            "data" => %{"name" => "Step", "code" => "line1\nline2\nline3"}
          }
        ],
        "edges" => []
      }

      body = "~~~json\n#{Jason.encode!(definition, pretty: true)}\n~~~"
      assert {:ok, parsed} = DefinitionParser.extract_definition(body)
      assert get_in(parsed, ["nodes", Access.at(0), "data", "code"]) == "line1\nline2\nline3"
    end

    test "rejects truncated JSON (missing closing brace)" do
      body = "~~~json\n{\"version\": \"1.0\", \"nodes\": [\n~~~"
      assert {:error, {:invalid_json, _}} = DefinitionParser.extract_definition(body)
    end

    test "accepts closing fence with trailing newline variants" do
      # no trailing newline after closing fence
      body = "~~~json\n#{Jason.encode!(@minimal_definition)}\n~~~"
      assert {:ok, _} = DefinitionParser.extract_definition(body)
    end
  end

  describe "classify/1" do
    test "returns {:edit, definition, summary} when JSON fence present" do
      body = """
      ~~~json
      #{Jason.encode!(@minimal_definition)}
      ~~~

      Summary: created the flow
      """

      assert {:edit, def, summary} = DefinitionParser.classify(body)
      assert def["version"] == "1.0"
      assert summary == "created the flow"
    end

    test "returns {:explain, text} when Answer: prefix is present" do
      body = "Answer: this flow receives an event and validates it."

      assert {:explain, "this flow receives an event and validates it."} =
               DefinitionParser.classify(body)
    end

    test "returns {:explain, text} with multiline Answer" do
      body = """
      Answer: The flow has 3 steps.

      - Validation
      - Processing
      - Response
      """

      assert {:explain, answer} = DefinitionParser.classify(body)
      assert answer =~ "3 steps"
      assert answer =~ "Validation"
    end

    test "falls back to {:explain, prose} when no fence and no Answer: prefix" do
      body = "The flow simply passes data forward without modifications."
      assert {:explain, text} = DefinitionParser.classify(body)
      assert text =~ "passes data"
    end

    test "returns {:error, :no_content} on empty response" do
      assert {:error, :no_content} = DefinitionParser.classify("   \n   ")
    end

    test "returns {:error, {:invalid_json, _}} when fence present but JSON invalid" do
      assert {:error, {:invalid_json, _}} =
               DefinitionParser.classify("~~~json\n{not valid\n~~~")
    end
  end

  describe "extract_summary/1" do
    test "returns the text after 'Summary:' line" do
      body = """
      ~~~json
      {}
      ~~~

      Summary: created an approval flow
      """

      assert "created an approval flow" = DefinitionParser.extract_summary(body)
    end

    test "returns default when no Summary: line is present" do
      assert "Flow generated by the agent" = DefinitionParser.extract_summary("~~~json\n{}\n~~~")
    end

    test "trims leading and trailing whitespace" do
      body = "~~~\n{}\n~~~\n\nSummary:    all good   \n"
      assert "all good" = DefinitionParser.extract_summary(body)
    end
  end
end
