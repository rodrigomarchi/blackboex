defmodule Blackboex.LLM.ClientBehaviourTest do
  use ExUnit.Case, async: true

  alias Blackboex.LLM.ClientBehaviour

  @moduletag :unit

  describe "ClientBehaviour" do
    test "defines generate_text/2 callback" do
      callbacks = ClientBehaviour.behaviour_info(:callbacks)
      assert {:generate_text, 2} in callbacks
    end

    test "defines stream_text/2 callback" do
      callbacks = ClientBehaviour.behaviour_info(:callbacks)
      assert {:stream_text, 2} in callbacks
    end
  end
end
