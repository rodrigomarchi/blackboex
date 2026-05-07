defmodule Blackboex.LLMTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.LLM

  setup :create_user_and_org

  describe "record_usage/1" do
    test "records LLM usage", %{user: user, org: org} do
      assert {:ok, usage} =
               LLM.record_usage(%{
                 user_id: user.id,
                 organization_id: org.id,
                 project_id: Blackboex.Projects.get_default_project(org.id).id,
                 provider: "anthropic",
                 model: "anthropic:claude-sonnet-4-5-20250929",
                 input_tokens: 100,
                 output_tokens: 200,
                 cost_cents: 5,
                 operation: "code_generation",
                 duration_ms: 1500
               })

      assert usage.provider == "anthropic"
      assert usage.input_tokens == 100
      assert usage.operation == "code_generation"
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = LLM.record_usage(%{})
      refute changeset.valid?
    end
  end
end
