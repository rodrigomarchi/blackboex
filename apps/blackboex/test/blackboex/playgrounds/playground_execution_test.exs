defmodule Blackboex.Playgrounds.PlaygroundExecutionTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Playgrounds.PlaygroundExecution

  describe "changeset/2" do
    test "valid changeset with required fields" do
      playground = playground_fixture()

      changeset =
        PlaygroundExecution.changeset(%PlaygroundExecution{}, %{
          playground_id: playground.id,
          run_number: 1,
          code_snapshot: "IO.puts(:hello)",
          status: "running"
        })

      assert changeset.valid?
    end

    test "requires playground_id" do
      changeset =
        PlaygroundExecution.changeset(%PlaygroundExecution{}, %{
          run_number: 1,
          code_snapshot: "IO.puts(:hello)",
          status: "running"
        })

      assert %{playground_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires run_number" do
      playground = playground_fixture()

      changeset =
        PlaygroundExecution.changeset(%PlaygroundExecution{}, %{
          playground_id: playground.id,
          code_snapshot: "IO.puts(:hello)",
          status: "running"
        })

      assert %{run_number: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires code_snapshot" do
      playground = playground_fixture()

      changeset =
        PlaygroundExecution.changeset(%PlaygroundExecution{}, %{
          playground_id: playground.id,
          run_number: 1,
          status: "running"
        })

      assert %{code_snapshot: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates status inclusion" do
      playground = playground_fixture()

      changeset =
        PlaygroundExecution.changeset(%PlaygroundExecution{}, %{
          playground_id: playground.id,
          run_number: 1,
          code_snapshot: "IO.puts(:hello)",
          status: "invalid"
        })

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "validates run_number is positive" do
      playground = playground_fixture()

      changeset =
        PlaygroundExecution.changeset(%PlaygroundExecution{}, %{
          playground_id: playground.id,
          run_number: 0,
          code_snapshot: "IO.puts(:hello)",
          status: "running"
        })

      assert %{run_number: [_msg]} = errors_on(changeset)
    end
  end

  describe "complete_changeset/2" do
    test "updates output, status, and duration" do
      execution = execution_fixture(%{status: "running", output: nil, duration_ms: nil})

      changeset =
        PlaygroundExecution.complete_changeset(execution, %{
          output: "hello\n:ok",
          status: "success",
          duration_ms: 150
        })

      assert changeset.valid?
      assert get_change(changeset, :output) == "hello\n:ok"
      assert get_change(changeset, :status) == "success"
      assert get_change(changeset, :duration_ms) == 150
    end

    test "validates status on complete" do
      execution = execution_fixture()

      changeset =
        PlaygroundExecution.complete_changeset(execution, %{
          status: "unknown"
        })

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "validates output max length" do
      execution = execution_fixture()
      long_output = String.duplicate("x", 65_537)

      changeset =
        PlaygroundExecution.complete_changeset(execution, %{
          output: long_output,
          status: "success"
        })

      assert %{output: [_msg]} = errors_on(changeset)
    end
  end

  describe "fixture" do
    test "execution_fixture creates a valid execution" do
      execution = execution_fixture()

      assert execution.id
      assert execution.playground_id
      assert execution.run_number == 1
      assert execution.code_snapshot == "IO.puts(:ok)"
      assert execution.output == "ok"
      assert execution.status == "success"
      assert execution.duration_ms == 42
    end
  end
end
