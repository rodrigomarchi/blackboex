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

  # ── run_generation: LLM failure on first call ──────────────────

  describe "run_generation with LLM failure" do
    setup [:create_api_with_run]

    test "returns error when code generation LLM call fails", %{api: api, run: run} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "API rate limit exceeded"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "API rate limit exceeded"}
      end)

      result =
        CodePipeline.run_generation(api, "Create a handler",
          run_id: run.id,
          broadcast_fn: fn _event -> :ok end
        )

      assert {:error, reason} = result
      assert reason =~ "LLM"
    end

    test "calls broadcast_fn with step_started and step_failed", %{api: api, run: run} do
      test_pid = self()

      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "API error"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "API error"}
      end)

      broadcast = fn event -> send(test_pid, {:broadcast, event}) end

      CodePipeline.run_generation(api, "Create a handler",
        run_id: run.id,
        broadcast_fn: broadcast
      )

      assert_received {:broadcast, {:step_started, %{step: :generating_code}}}
      assert_received {:broadcast, {:step_failed, %{step: :generating_code, error: _}}}
    end
  end

  # ── guarded_llm_call: max calls exceeded ───────────────────────

  describe "max LLM calls guard" do
    setup [:create_api_with_run]

    test "stops after exceeding max total LLM calls", %{api: api, run: run} do
      call_count = :counters.new(1, [:atomics])

      # No streaming — force sync path so we don't need to construct StreamResponse
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        :counters.add(call_count, 1, 1)
        # Return non-StreamResponse to trigger sync fallback
        raise "force sync fallback"
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        :counters.add(call_count, 1, 1)
        # Always return code that fails compilation so pipeline retries
        {:ok, %{content: "```elixir\ndef handle(p), do: p\n```"}}
      end)

      result =
        CodePipeline.run_generation(api, "Create a handler",
          run_id: run.id,
          token_callback: fn _t -> :ok end,
          broadcast_fn: fn _event -> :ok end
        )

      # Pipeline should eventually error out (either from max calls or max retries)
      assert {:error, _reason} = result
      # Verify it didn't go infinite — should be bounded
      total_calls = :counters.get(call_count, 1)
      assert total_calls <= 20
    end
  end

  # ── run_generation: broadcast events ───────────────────────────

  describe "run_generation broadcasts pipeline events" do
    setup [:create_api_with_run]

    test "broadcasts step_started for generating_code step", %{api: api, run: run} do
      test_pid = self()

      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "fail fast"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "fail fast"}
      end)

      broadcast = fn event -> send(test_pid, {:broadcast, event}) end

      CodePipeline.run_generation(api, "Create handler",
        run_id: run.id,
        broadcast_fn: broadcast
      )

      assert_received {:broadcast, {:step_started, %{step: :generating_code}}}
    end
  end

  # ── run_edit: basic path ───────────────────────────────────────

  describe "run_edit" do
    setup [:create_api_with_run]

    test "returns error when edit LLM call fails", %{api: api, run: run} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "LLM unavailable"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "LLM unavailable"}
      end)

      result =
        CodePipeline.run_edit(
          api,
          "Add validation",
          "def handle(p), do: p",
          "test \"basic\" do end",
          run_id: run.id,
          broadcast_fn: fn _event -> :ok end
        )

      assert {:error, reason} = result
      assert reason =~ "LLM"
    end

    test "broadcasts generating_code step for edit", %{api: api, run: run} do
      test_pid = self()

      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "fail"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "fail"}
      end)

      broadcast = fn event -> send(test_pid, {:broadcast, event}) end

      CodePipeline.run_edit(
        api,
        "Add validation",
        "def handle(p), do: p",
        "",
        run_id: run.id,
        broadcast_fn: broadcast
      )

      assert_received {:broadcast, {:step_started, %{step: :generating_code}}}
    end
  end

  # ── default broadcast_fn ───────────────────────────────────────

  describe "default broadcast_fn" do
    setup [:create_api_with_run]

    test "run_generation works without explicit broadcast_fn", %{api: api, run: run} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "no LLM"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "no LLM"}
      end)

      # Should not crash even without broadcast_fn
      result = CodePipeline.run_generation(api, "Create handler", run_id: run.id)
      assert {:error, _} = result
    end

    test "run_edit works without explicit broadcast_fn", %{api: api, run: run} do
      Blackboex.LLM.ClientMock
      |> stub(:stream_text, fn _prompt, _opts ->
        {:error, "no LLM"}
      end)
      |> stub(:generate_text, fn _prompt, _opts ->
        {:error, "no LLM"}
      end)

      result = CodePipeline.run_edit(api, "edit", "code", "tests", run_id: run.id)
      assert {:error, _} = result
    end
  end

  # ── stream_reset broadcast on stream failure ──────────────────

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
