defmodule Blackboex.Testing.TestSuite do
  @moduledoc """
  Schema for auto-generated test suites. Each suite belongs to an API
  and stores LLM-generated ExUnit test code with execution results.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(pending running passed failed error)
  @max_test_code_bytes 1_048_576

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "test_suites" do
    field :version_number, :integer
    field :test_code, :string
    field :status, :string, default: "pending"
    field :results, {:array, :map}, default: []
    field :total_tests, :integer, default: 0
    field :passed_tests, :integer, default: 0
    field :failed_tests, :integer, default: 0
    field :duration_ms, :integer, default: 0

    belongs_to :api, Blackboex.Apis.Api
    belongs_to :project, Blackboex.Projects.Project

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(suite, attrs) do
    suite
    |> cast(attrs, [
      :api_id,
      :project_id,
      :version_number,
      :test_code,
      :status,
      :results,
      :total_tests,
      :passed_tests,
      :failed_tests,
      :duration_ms
    ])
    |> validate_required([:api_id, :project_id, :test_code])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:total_tests, greater_than_or_equal_to: 0)
    |> validate_number(:passed_tests, greater_than_or_equal_to: 0)
    |> validate_number(:failed_tests, greater_than_or_equal_to: 0)
    |> validate_number(:version_number, greater_than_or_equal_to: 0)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> validate_length(:test_code, max: @max_test_code_bytes)
    |> foreign_key_constraint(:api_id)
    |> unique_constraint([:api_id, :version_number])
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
