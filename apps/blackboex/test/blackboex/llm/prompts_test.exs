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

  describe "build_generation_prompt/2" do
    test "includes user description" do
      prompt = Prompts.build_generation_prompt("Convert Celsius to Fahrenheit", :computation)
      assert prompt =~ "Convert Celsius to Fahrenheit"
    end

    test "includes computation template for :computation type" do
      prompt = Prompts.build_generation_prompt("Calculate factorial", :computation)
      assert prompt =~ "computation"
    end

    test "includes crud template for :crud type" do
      prompt = Prompts.build_generation_prompt("Store user data", :crud)
      assert prompt =~ "CRUD"
    end

    test "includes webhook template for :webhook type" do
      prompt = Prompts.build_generation_prompt("Receive Stripe events", :webhook)
      assert prompt =~ "webhook"
    end
  end
end
