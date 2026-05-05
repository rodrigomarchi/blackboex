defmodule Blackboex.Plans.PlanTask do
  @moduledoc """
  A single task inside a `Plan`. Tasks are ordered (`order` is unique per
  plan) and dispatched sequentially by the `PlanRunnerWorker` to the
  matching per-artifact KickoffWorker.

  Status lifecycle:

      pending → running → done | failed

  `:skipped` is a creation-time-only status: it is set when copying prior
  `:done` tasks onto a re-plan via `Plans.start_continuation/2`. The
  changeset rejects any later transition into `:skipped`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_artifact_types ~w(api flow page playground)
  @valid_actions ~w(create edit)
  @valid_statuses ~w(pending running done failed skipped)

  @max_title_chars 300
  @max_error_message_bytes 65_536

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "plan_tasks" do
    field :order, :integer
    field :artifact_type, :string
    field :action, :string
    field :target_artifact_id, :binary_id
    field :title, :string
    field :params, :map, default: %{}
    field :acceptance_criteria, {:array, :string}, default: []
    field :status, :string, default: "pending"
    field :child_run_id, :binary_id
    field :error_message, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :plan, Blackboex.Plans.Plan

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :plan_id,
      :order,
      :artifact_type,
      :action,
      :target_artifact_id,
      :title,
      :params,
      :acceptance_criteria,
      :status,
      :child_run_id,
      :error_message,
      :started_at,
      :finished_at
    ])
    |> validate_required([:plan_id, :order, :artifact_type, :action, :title, :status])
    |> validate_inclusion(:artifact_type, @valid_artifact_types)
    |> validate_inclusion(:action, @valid_actions)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:order, greater_than_or_equal_to: 0)
    |> validate_length(:title, max: @max_title_chars)
    |> validate_length(:error_message, max: @max_error_message_bytes)
    |> validate_skipped_only_at_insert(task)
    |> unique_constraint([:plan_id, :order])
    |> foreign_key_constraint(:plan_id)
  end

  # `:skipped` is a creation-time-only status. The runner must never
  # transition a task into `:skipped` from another state.
  defp validate_skipped_only_at_insert(changeset, %{__meta__: %{state: :built}}), do: changeset

  defp validate_skipped_only_at_insert(changeset, _existing) do
    case fetch_change(changeset, :status) do
      {:ok, "skipped"} ->
        add_error(
          changeset,
          :status,
          "cannot transition into :skipped; status is creation-time-only"
        )

      _ ->
        changeset
    end
  end

  @spec valid_artifact_types() :: [String.t()]
  def valid_artifact_types, do: @valid_artifact_types

  @spec valid_actions() :: [String.t()]
  def valid_actions, do: @valid_actions

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
