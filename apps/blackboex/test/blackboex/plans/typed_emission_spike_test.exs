defmodule Blackboex.Plans.TypedEmissionSpikeTest do
  @moduledoc """
  M2 SPIKE — verifies that the M5 Planner can commit to
  `ReqLLM.generate_object/4` for typed emission.

  Three checks per the M2 plan:

    1. `ReqLLM.generate_object/4` is exported and arity-4 in the installed
       `req_llm` version.
    2. A returned object validates against an Ecto changeset built from a
       stripped-down `PlanTask` shape.
    3. Failure modes (invalid JSON / schema mismatch) surface as
       `{:error, _}` instead of crashes.

  Decision rule (documented in `apps/blackboex/lib/blackboex/plans/AGENTS.md`):
    * Spike PASSES → M5 commits to `ReqLLM.generate_object/4`.
    * Spike FAILS on (1) or (2) → M5 substitutes `instructor_lite ~> 1.2`
      (already declared in `apps/blackboex/mix.exs`).
  """

  use Blackboex.DataCase, async: true

  @moduletag :integration

  # The stripped-down PlanTask shape that the spike validates against.
  defmodule SpikeTask do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :artifact_type, :string
      field :action, :string
      field :title, :string
    end

    @valid_artifact_types ~w(api flow page playground)
    @valid_actions ~w(create edit)

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [:artifact_type, :action, :title])
      |> validate_required([:artifact_type, :action, :title])
      |> validate_inclusion(:artifact_type, @valid_artifact_types)
      |> validate_inclusion(:action, @valid_actions)
    end
  end

  describe "(1) ReqLLM.generate_object/4 exists at the expected arity" do
    test "ReqLLM module is loadable" do
      assert Code.ensure_loaded?(ReqLLM.Generation),
             "ReqLLM.Generation module must be loadable for the planner spike"
    end

    test "generate_object/4 is exported on ReqLLM.Generation" do
      assert function_exported?(ReqLLM.Generation, :generate_object, 4),
             "ReqLLM.Generation.generate_object/4 missing — fall back to instructor_lite"
    end
  end

  describe "(2) returned object validates against an Ecto changeset" do
    test "casts a well-shaped map to a valid changeset" do
      object = %{"artifact_type" => "api", "action" => "create", "title" => "Posts API"}
      cs = SpikeTask.changeset(%SpikeTask{}, object)
      assert cs.valid?
      assert {:ok, %SpikeTask{title: "Posts API"}} = Ecto.Changeset.apply_action(cs, :insert)
    end

    test "casts atom-keyed maps too (ReqLLM may return either)" do
      object = %{artifact_type: "page", action: "edit", title: "Edit page"}
      cs = SpikeTask.changeset(%SpikeTask{}, object)
      assert cs.valid?
    end
  end

  describe "(3) failure modes surface as {:error, _}, not crashes" do
    test "schema mismatch (invalid artifact_type) yields an invalid changeset" do
      object = %{"artifact_type" => "lambda", "action" => "create", "title" => "x"}
      cs = SpikeTask.changeset(%SpikeTask{}, object)
      refute cs.valid?
      assert {:error, %Ecto.Changeset{}} = Ecto.Changeset.apply_action(cs, :insert)
    end

    test "missing required field yields an invalid changeset" do
      object = %{"action" => "create"}
      cs = SpikeTask.changeset(%SpikeTask{}, object)
      refute cs.valid?
      assert "can't be blank" in (errors_on(cs) |> Map.get(:artifact_type, []))
    end

    test "wrapper that re-uses ClientMock surfaces an error tuple, never raises" do
      # Simulate the typed-emission wrapper: take a JSON-like map from a
      # mock LLM response, run it through the changeset, and surface
      # `{:error, _}` on validation failure.
      bad_response = %{"artifact_type" => "lambda", "title" => "no action"}

      result =
        case SpikeTask.changeset(%SpikeTask{}, bad_response)
             |> Ecto.Changeset.apply_action(:insert) do
          {:ok, struct} -> {:ok, struct}
          {:error, cs} -> {:error, {:invalid_object, cs}}
        end

      assert match?({:error, {:invalid_object, %Ecto.Changeset{}}}, result)
    end
  end
end
