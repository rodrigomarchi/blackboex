defmodule Blackboex.PlaygroundAgent.StreamManagerTest do
  use ExUnit.Case, async: false

  alias Blackboex.PlaygroundAgent.StreamManager

  setup do
    run_id = Ecto.UUID.generate()
    Phoenix.PubSub.subscribe(Blackboex.PubSub, "playground_agent:run:#{run_id}")
    {:ok, run_id: run_id}
  end

  describe "build_token_callback/1 (fence-aware)" do
    test "does not emit prose before the opening fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("Claro, aqui vai:\n")
      refute_receive {:code_delta, _}, 50
    end

    test "emits only the code inside the elixir fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)

      # Prose + opening fence + code
      Enum.each(
        ["Claro, aqui vai:\n", "```elixir\n", "IO.puts(:ok)\n", "x = 1\n"],
        &cb.(&1)
      )

      # Force flush everything we've emitted so far
      StreamManager.flush_remaining(run_id)

      emitted =
        collect_deltas([])
        |> Enum.join()

      assert emitted =~ "IO.puts(:ok)"
      assert emitted =~ "x = 1"
      refute emitted =~ "Claro"
      refute emitted =~ "```"
    end

    test "stops emitting once the closing fence arrives", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)

      Enum.each(
        [
          "```elixir\n",
          "IO.puts(:ok)\n",
          "```\n",
          "Resumo: escreve ok\n"
        ],
        &cb.(&1)
      )

      StreamManager.flush_remaining(run_id)

      emitted = collect_deltas([]) |> Enum.join()
      assert emitted =~ "IO.puts(:ok)"
      refute emitted =~ "Resumo"
      refute emitted =~ "```"
    end

    test "handles a generic ``` fence (no language)", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      Enum.each(["```\n", "a = 1\n", "b = 2\n"], &cb.(&1))
      StreamManager.flush_remaining(run_id)

      emitted = collect_deltas([]) |> Enum.join()
      assert emitted =~ "a = 1"
      assert emitted =~ "b = 2"
      refute emitted =~ "```"
    end

    test "resets state between runs (no cross-contamination)",
         %{run_id: run_id} do
      cb1 = StreamManager.build_token_callback(run_id)
      cb1.("leftover text without fence")

      # A second callback build should reset internal state
      StreamManager.build_token_callback(run_id)
      # The second callback should start fresh — no emission yet.
      refute_receive {:code_delta, _}, 50
    end
  end

  describe "flush_remaining/1" do
    test "no-op when never inside a fence", %{run_id: run_id} do
      cb = StreamManager.build_token_callback(run_id)
      cb.("only prose, no code")
      StreamManager.flush_remaining(run_id)
      refute_receive {:code_delta, _}, 50
    end
  end

  defp collect_deltas(acc) do
    receive do
      {:code_delta, %{delta: delta}} -> collect_deltas([delta | acc])
    after
      30 -> Enum.reverse(acc)
    end
  end

  describe "broadcast helpers" do
    test "broadcast_run sends to the run topic", %{run_id: run_id} do
      StreamManager.broadcast_run(run_id, {:run_completed, %{code: "x"}})
      assert_receive {:run_completed, %{code: "x"}}, 100
    end

    test "broadcast_playground sends to the playground topic" do
      pg_id = Ecto.UUID.generate()
      Phoenix.PubSub.subscribe(Blackboex.PubSub, "playground_agent:playground:#{pg_id}")
      StreamManager.broadcast_playground(pg_id, {:run_started, %{foo: 1}})
      assert_receive {:run_started, %{foo: 1}}, 100
    end
  end
end
