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
      Vou montar o fluxo:

      ~~~json
      #{Jason.encode!(@minimal_definition)}
      ~~~

      Resumo: fluxo básico
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
      Claro! Aqui está o fluxo pedido:

      ~~~json
      #{Jason.encode!(@minimal_definition)}
      ~~~

      Resumo: pronto.
      Outra linha qualquer.
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

      Resumo: criei o fluxo
      """

      assert {:edit, def, summary} = DefinitionParser.classify(body)
      assert def["version"] == "1.0"
      assert summary == "criei o fluxo"
    end

    test "returns {:explain, text} when Resposta: prefix is present" do
      body = "Resposta: esse fluxo recebe um evento e valida."
      assert {:explain, "esse fluxo recebe um evento e valida."} = DefinitionParser.classify(body)
    end

    test "returns {:explain, text} with Resposta multi-linha" do
      body = """
      Resposta: O fluxo tem 3 etapas.

      - Validação
      - Processamento
      - Resposta
      """

      assert {:explain, answer} = DefinitionParser.classify(body)
      assert answer =~ "3 etapas"
      assert answer =~ "Validação"
    end

    test "falls back to {:explain, prose} when no fence and no Resposta: prefix" do
      body = "O fluxo simplesmente passa os dados adiante sem modificações."
      assert {:explain, text} = DefinitionParser.classify(body)
      assert text =~ "passa os dados"
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
    test "returns the text after 'Resumo:' line" do
      body = """
      ~~~json
      {}
      ~~~

      Resumo: criei um fluxo de aprovação
      """

      assert "criei um fluxo de aprovação" = DefinitionParser.extract_summary(body)
    end

    test "returns default when no Resumo: line is present" do
      assert "Fluxo gerado pelo agente" = DefinitionParser.extract_summary("~~~json\n{}\n~~~")
    end

    test "trims leading and trailing whitespace" do
      body = "~~~\n{}\n~~~\n\nResumo:    tudo ok   \n"
      assert "tudo ok" = DefinitionParser.extract_summary(body)
    end
  end
end
