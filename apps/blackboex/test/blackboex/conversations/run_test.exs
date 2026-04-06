defmodule Blackboex.Conversations.RunTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Conversations
  alias Blackboex.Conversations.Run

  setup do
    {user, org} = user_and_org_fixture()

    {:ok, api} =
      Blackboex.Apis.create_api(%{name: "Run Test", organization_id: org.id, user_id: user.id})

    conversation = conversation_fixture(api.id, org.id)
    %{user: user, org: org, api: api, conversation: conversation}
  end

  defp valid_attrs(context) do
    %{
      conversation_id: context.conversation.id,
      api_id: context.api.id,
      user_id: context.user.id,
      organization_id: context.org.id,
      run_type: "generation"
    }
  end

  # ── valid_run_types/0 ───────────────────────────────────────────

  describe "valid_run_types/0" do
    test "returns expected list of strings" do
      assert Run.valid_run_types() == ~w(generation edit test_only doc_only)
    end
  end

  # ── valid_statuses/0 ───────────────────────────────────────────

  describe "valid_statuses/0" do
    test "returns expected list of strings" do
      assert Run.valid_statuses() == ~w(pending running completed failed cancelled partial)
    end
  end

  # ── changeset/2 ────────────────────────────────────────────────

  describe "changeset/2" do
    test "valid with all required fields", context do
      changeset = Run.changeset(%Run{}, valid_attrs(context))
      assert changeset.valid?
    end

    test "invalid when missing required fields" do
      changeset = Run.changeset(%Run{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :conversation_id)
      assert Map.has_key?(errors, :api_id)
      assert Map.has_key?(errors, :user_id)
      assert Map.has_key?(errors, :organization_id)
      assert Map.has_key?(errors, :run_type)
    end

    test "invalid with unknown run_type", context do
      attrs = Map.put(valid_attrs(context), :run_type, "invalid_type")
      changeset = Run.changeset(%Run{}, attrs)
      refute changeset.valid?
      assert %{run_type: [_]} = errors_on(changeset)
    end

    test "valid with each valid run_type", context do
      for run_type <- Run.valid_run_types() do
        attrs = Map.put(valid_attrs(context), :run_type, run_type)
        changeset = Run.changeset(%Run{}, attrs)
        assert changeset.valid?, "Expected run_type #{run_type} to be valid"
      end
    end

    test "invalid with unknown status", context do
      attrs = Map.put(valid_attrs(context), :status, "bogus")
      changeset = Run.changeset(%Run{}, attrs)
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "valid with each valid status", context do
      for status <- Run.valid_statuses() do
        attrs = Map.put(valid_attrs(context), :status, status)
        changeset = Run.changeset(%Run{}, attrs)
        assert changeset.valid?, "Expected status #{status} to be valid"
      end
    end

    test "status defaults to pending when not provided", context do
      changeset = Run.changeset(%Run{}, valid_attrs(context))
      assert get_field(changeset, :status) == "pending"
    end

    test "accepts optional trigger_message", context do
      attrs = Map.put(valid_attrs(context), :trigger_message, "Generate a hello world endpoint")
      changeset = Run.changeset(%Run{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :trigger_message) == "Generate a hello world endpoint"
    end

    test "accepts optional config map", context do
      attrs = Map.put(valid_attrs(context), :config, %{"model" => "gpt-4"})
      changeset = Run.changeset(%Run{}, attrs)
      assert changeset.valid?
    end
  end

  # ── completion_changeset/2 ──────────────────────────────────────

  describe "completion_changeset/2" do
    test "sets completed_at", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))
      now = DateTime.utc_now()
      changeset = Run.completion_changeset(run, %{completed_at: now, status: "completed"})
      assert changeset.valid?
      assert get_change(changeset, :completed_at) == now
    end

    test "sets duration_ms", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))
      changeset = Run.completion_changeset(run, %{duration_ms: 1500, status: "completed"})
      assert changeset.valid?
      assert get_change(changeset, :duration_ms) == 1500
    end

    test "sets final_code when status is completed", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))

      changeset =
        Run.completion_changeset(run, %{
          status: "completed",
          final_code: "def hello, do: :world"
        })

      assert changeset.valid?
      assert get_change(changeset, :final_code) == "def hello, do: :world"
      assert get_change(changeset, :status) == "completed"
    end

    test "sets error_summary when status is failed", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))

      changeset =
        Run.completion_changeset(run, %{
          status: "failed",
          error_summary: "Compilation failed: undefined variable x"
        })

      assert changeset.valid?
      assert get_change(changeset, :error_summary) == "Compilation failed: undefined variable x"
      assert get_change(changeset, :status) == "failed"
    end

    test "rejects invalid status", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))
      changeset = Run.completion_changeset(run, %{status: "unknown"})
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end
  end

  # ── metrics_changeset/2 ─────────────────────────────────────────

  describe "metrics_changeset/2" do
    test "updates input_tokens, output_tokens, and event_count", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))

      changeset =
        Run.metrics_changeset(run, %{input_tokens: 100, output_tokens: 250, event_count: 5})

      assert changeset.valid?
      assert get_change(changeset, :input_tokens) == 100
      assert get_change(changeset, :output_tokens) == 250
      assert get_change(changeset, :event_count) == 5
    end

    test "sets started_at", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))
      now = DateTime.utc_now()
      changeset = Run.metrics_changeset(run, %{started_at: now})
      assert changeset.valid?
      assert get_change(changeset, :started_at) == now
    end

    test "updates model and fallback_model", context do
      {:ok, run} = Conversations.create_run(valid_attrs(context))

      changeset =
        Run.metrics_changeset(run, %{model: "gpt-4o", fallback_model: "gpt-3.5-turbo"})

      assert changeset.valid?
      assert get_change(changeset, :model) == "gpt-4o"
      assert get_change(changeset, :fallback_model) == "gpt-3.5-turbo"
    end
  end

  # ── admin_changeset/3 ───────────────────────────────────────────

  describe "admin_changeset/3" do
    test "behaves like changeset with valid attrs", context do
      changeset = Run.admin_changeset(%Run{}, valid_attrs(context), %{actor: "admin"})
      assert changeset.valid?
    end

    test "accepts metadata argument without error", context do
      metadata = %{actor: "admin@example.com", ip: "127.0.0.1"}
      changeset = Run.admin_changeset(%Run{}, valid_attrs(context), metadata)
      assert changeset.valid?
    end

    test "still validates required fields with metadata", do: do_admin_changeset_required_test()

    defp do_admin_changeset_required_test do
      changeset = Run.admin_changeset(%Run{}, %{}, %{})
      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :run_type)
    end
  end
end
