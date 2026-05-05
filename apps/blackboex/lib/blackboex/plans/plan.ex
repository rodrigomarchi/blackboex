defmodule Blackboex.Plans.Plan do
  @moduledoc """
  A typed multi-step plan produced by the Project Agent. The plan is emitted
  as structured data, rendered to markdown for the user to review/edit, and
  re-validated against the schema on approval before any work runs.

  Lifecycle:

      draft → approved → running → done | partial | failed

  `:draft` plans are mutable. After `:approved`, the plan is immutable —
  "Continue from partial" creates a new draft `Plan` with `parent_plan_id`
  pointing to its predecessor (re-plan). The DB enforces "at most one
  active plan per project" via a UNIQUE-partial index on
  `(project_id) WHERE status IN ('approved','running')`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(draft approved running done partial failed)

  @max_title_chars 200
  @max_user_message_chars 10_000
  @max_markdown_body_bytes 1_048_576
  @max_failure_reason_bytes 65_536

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "plans" do
    field :status, :string, default: "draft"
    field :title, :string
    field :user_message, :string
    field :markdown_body, :string
    field :model_tier_caps, :map, default: %{}
    field :approved_at, :utc_datetime_usec
    field :failure_reason, :string

    belongs_to :project, Blackboex.Projects.Project
    belongs_to :run, Blackboex.ProjectConversations.ProjectRun
    belongs_to :parent_plan, Blackboex.Plans.Plan

    belongs_to :approved_by_user, Blackboex.Accounts.User,
      foreign_key: :approved_by_user_id,
      type: :id

    has_many :tasks, Blackboex.Plans.PlanTask, foreign_key: :plan_id

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :project_id,
      :run_id,
      :parent_plan_id,
      :status,
      :title,
      :user_message,
      :markdown_body,
      :model_tier_caps,
      :approved_by_user_id,
      :approved_at,
      :failure_reason
    ])
    |> validate_required([:project_id, :status, :title, :user_message, :markdown_body])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:title, max: @max_title_chars)
    |> validate_length(:user_message, max: @max_user_message_chars)
    |> validate_length(:markdown_body, max: @max_markdown_body_bytes)
    |> validate_length(:failure_reason, max: @max_failure_reason_bytes)
    |> unique_constraint(:project_id, name: :plans_one_active_per_project_idx)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:parent_plan_id)
    |> foreign_key_constraint(:approved_by_user_id)
  end

  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(plan, attrs) do
    plan
    |> cast(attrs, [:status, :failure_reason, :approved_by_user_id, :approved_at, :run_id])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:failure_reason, max: @max_failure_reason_bytes)
    |> unique_constraint(:project_id, name: :plans_one_active_per_project_idx)
  end

  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
