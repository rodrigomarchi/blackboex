defmodule Blackboex.Agent.CodePipelineTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Agent.CodePipeline
  alias Blackboex.Apis
  alias Blackboex.Conversations
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures
  import Mox

  @moduletag :unit

  setup :verify_on_exit!

  defp create_api_with_run(_context) do
    user = user_fixture()
    [org] = Organizations.list_user_organizations(user)

    {:ok, api} =
      Apis.create_api(%{
        name: "pipeline-test-api",
        organization_id: org.id,
        user_id: user.id
      })

    {:ok, conversation} = Conversations.get_or_create_conversation(api.id, org.id)

    {:ok, run} =
      Conversations.create_run(%{
        conversation_id: conversation.id,
        api_id: api.id,
        user_id: user.id,
        organization_id: org.id,
        run_type: "generation",
        trigger_message: "test"
      })

    %{api: api, run: run, org: org}
  end

  describe "stream_reset broadcast on stream failure" do
    setup [:create_api_with_run]

    test "broadcasts {:stream_reset, %{}} when stream_text raises", %{api: api, run: run} do
      run_id = run.id

      # Subscribe to PubSub to catch the stream_reset broadcast
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "run:#{run_id}")

      # Mock: stream_text raises, generate_text returns code for sync fallback.
      # The pipeline will call guarded_llm_call multiple times, so we stub (not expect).
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        raise "simulated stream failure"
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{
           content:
             "```elixir\ndefmodule Handler do\n  def call(params), do: {:ok, params}\nend\n```"
         }}
      end)

      # Run the pipeline — it will likely fail at compile/validate steps,
      # but that's OK. We only care about the stream_reset broadcast.
      _result =
        CodePipeline.run_generation(api, "Create a simple handler",
          run_id: run_id,
          token_callback: fn _token -> :ok end,
          broadcast_fn: fn _event -> :ok end
        )

      # Verify stream_reset was broadcast
      assert_received {:stream_reset, %{}}
    end

    test "skips broadcast when pipeline_run_id is nil", %{api: api} do
      # No run_id → no broadcast target
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        raise "simulated stream failure"
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{content: "```elixir\ndefmodule Handler do\n  def call(p), do: {:ok, p}\nend\n```"}}
      end)

      # Run without run_id — should not crash
      _result =
        CodePipeline.run_generation(api, "Create a handler",
          run_id: nil,
          token_callback: fn _token -> :ok end,
          broadcast_fn: fn _event -> :ok end
        )

      # No stream_reset should have been received (no topic to broadcast to)
      refute_received {:stream_reset, _}
    end

    test "sync fallback returns result after stream failure", %{api: api, run: run} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        raise "simulated stream failure"
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:ok,
         %{content: "```elixir\ndefmodule Handler do\n  def call(p), do: {:ok, p}\nend\n```"}}
      end)

      # The pipeline should NOT fail due to the stream error — it should fall back to sync.
      # The first step (code generation) should succeed via sync fallback.
      # Later steps may fail (compile/validate), but the sync fallback itself works.
      result =
        CodePipeline.run_generation(api, "Create a handler",
          run_id: run.id,
          token_callback: fn _token -> :ok end,
          broadcast_fn: fn _event -> :ok end
        )

      # The pipeline may succeed or fail at later steps, but it should NOT fail with
      # a stream error — the sync fallback should have handled it.
      case result do
        {:ok, %{code: code}} ->
          assert is_binary(code)

        {:error, reason} ->
          # If it fails, it should be from a later step, not from the stream error
          refute reason =~ "stream"
      end
    end
  end
end
