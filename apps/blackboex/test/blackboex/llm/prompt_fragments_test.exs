defmodule Blackboex.LLM.PromptFragmentsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.PromptFragments

  describe "handler_rules/0" do
    test "contains critical handler constraints" do
      rules = PromptFragments.handler_rules()

      assert rules =~ "conn"
      assert rules =~ "Plug"
      assert rules =~ "plain map"
      assert rules =~ "Request"
      assert rules =~ "Response"
      assert rules =~ "String.to_atom"
    end
  end

  describe "allowed_and_prohibited_modules/0" do
    test "includes allowed modules from SecurityConfig" do
      modules = PromptFragments.allowed_and_prohibited_modules()

      assert modules =~ "Enum"
      assert modules =~ "Map"
      assert modules =~ "String"
    end

    test "includes prohibited modules from SecurityConfig" do
      modules = PromptFragments.allowed_and_prohibited_modules()

      assert modules =~ "File"
      assert modules =~ "System"
      assert modules =~ "Code"
      assert modules =~ "Port"
    end
  end

  describe "documentation_standards/0" do
    test "requires moduledoc, doc, and spec" do
      standards = PromptFragments.documentation_standards()

      assert standards =~ "@moduledoc"
      assert standards =~ "@doc"
      assert standards =~ "@spec"
    end
  end

  describe "elixir_syntax_rules/0" do
    test "warns about elsif" do
      rules = PromptFragments.elixir_syntax_rules()

      assert rules =~ "elsif"
      assert rules =~ "DOES NOT EXIST"
      assert rules =~ "cond do"
    end
  end

  describe "code_quality_rules/0" do
    test "enforces line length, function size, and nesting" do
      rules = PromptFragments.code_quality_rules()

      assert rules =~ "120 characters"
      assert rules =~ "40 lines"
      assert rules =~ "4 levels of nesting"
      assert rules =~ "@doc"
      assert rules =~ "@spec"
    end
  end

  describe "function_decomposition/0" do
    test "includes decomposition guidance with example" do
      decomp = PromptFragments.function_decomposition()

      assert decomp =~ "40 lines"
      assert decomp =~ "defp"
      assert decomp =~ "compute_base_rate"
    end
  end

  describe "schema_rules/0" do
    test "covers Request, Response, and embeds patterns" do
      rules = PromptFragments.schema_rules()

      assert rules =~ "defmodule Request"
      assert rules =~ "defmodule Response"
      assert rules =~ "Blackboex.Schema"
      assert rules =~ "embeds_one"
      assert rules =~ "embeds_many"
      assert rules =~ "changeset/2"
    end
  end

  describe "search_replace_format/0" do
    test "includes SEARCH/REPLACE block format" do
      format = PromptFragments.search_replace_format()

      assert format =~ "<<<<<<< SEARCH"
      assert format =~ "======="
      assert format =~ ">>>>>>> REPLACE"
      assert format =~ "EXACTLY"
    end
  end

  describe "test_rules/0" do
    test "includes Handler module usage and float rules" do
      rules = PromptFragments.test_rules()

      assert rules =~ "Handler"
      assert rules =~ "handle(params)"
      assert rules =~ "float"
      assert rules =~ "0.1"
      assert rules =~ "DELETE those tests"
    end
  end

  describe "elixir_best_practices/0" do
    test "includes pattern matching and pipe operator guidance" do
      practices = PromptFragments.elixir_best_practices()

      assert practices =~ "Pattern match"
      assert practices =~ "|>"
      assert practices =~ "guard clauses"
    end
  end
end
