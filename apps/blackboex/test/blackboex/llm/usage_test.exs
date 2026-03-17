defmodule Blackboex.LLM.UsageTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.LLM.Usage

  import Blackboex.AccountsFixtures

  setup do
    user = user_fixture()

    {:ok, %{organization: org}} =
      Blackboex.Organizations.create_organization(user, %{name: "Test Org"})

    %{user: user, org: org}
  end

  describe "changeset/2" do
    test "valid with required fields", %{user: user, org: org} do
      attrs = %{
        user_id: user.id,
        organization_id: org.id,
        provider: "anthropic",
        model: "anthropic:claude-sonnet-4-20250514",
        input_tokens: 100,
        output_tokens: 200,
        cost_cents: 5,
        operation: "code_generation",
        duration_ms: 1500
      }

      changeset = Usage.changeset(%Usage{}, attrs)
      assert changeset.valid?
    end

    test "requires provider" do
      changeset = Usage.changeset(%Usage{}, %{})
      refute changeset.valid?
      assert %{provider: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
