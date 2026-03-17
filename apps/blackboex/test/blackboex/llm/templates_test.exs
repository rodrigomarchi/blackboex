defmodule Blackboex.LLM.TemplatesTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.LLM.Templates

  describe "get/1" do
    test "computation template returns wrapper for pure function" do
      template = Templates.get(:computation)
      assert template =~ "computation"
      assert template =~ "params"
      assert template =~ "json"
    end

    test "crud template returns wrapper with CRUD operations" do
      template = Templates.get(:crud)
      assert template =~ "CRUD"
      assert template =~ "create"
      assert template =~ "list"
    end

    test "webhook template returns wrapper for payload processing" do
      template = Templates.get(:webhook)
      assert template =~ "webhook"
      assert template =~ "payload"
    end
  end
end
