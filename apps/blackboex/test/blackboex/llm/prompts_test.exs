defmodule Blackboex.LLM.PromptsTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.Prompts

  describe "system_prompt/0" do
    test "contains security instructions" do
      prompt = Prompts.system_prompt()
      assert prompt =~ "NEVER"
      assert prompt =~ "File"
      assert prompt =~ "System"
    end

    test "instructs to return only function definitions" do
      prompt = Prompts.system_prompt()
      assert prompt =~ "handler"
      assert prompt =~ "function definitions"
    end

    test "contains allowed modules list" do
      prompt = Prompts.system_prompt()
      assert prompt =~ "Enum"
      assert prompt =~ "Map"
      assert prompt =~ "String"
    end

    test "contains prohibited modules list" do
      prompt = Prompts.system_prompt()
      assert prompt =~ "File"
      assert prompt =~ "System"
      assert prompt =~ "Code"
      assert prompt =~ "Port"
    end
  end
end
