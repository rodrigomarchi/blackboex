defmodule Blackboex.Apis.ApiVersion do
  @moduledoc """
  Schema for API code versions. Each save/generation/rollback creates a new version.
  Stores full source code, compilation status, and diff summary.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_sources ~w(generation manual_edit chat_edit rollback)
  @valid_compilation_statuses ~w(pending success error)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_versions" do
    field :version_number, :integer
    field :code, :string
    field :test_code, :string
    field :source, :string
    field :prompt, :string
    field :llm_response, :string
    field :compilation_status, :string, default: "pending"
    field :compilation_errors, {:array, :string}, default: []
    field :diff_summary, :string

    belongs_to :api, Blackboex.Apis.Api
    belongs_to :created_by, Blackboex.Accounts.User, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :api_id,
      :version_number,
      :code,
      :test_code,
      :source,
      :prompt,
      :llm_response,
      :compilation_status,
      :compilation_errors,
      :diff_summary,
      :created_by_id
    ])
    |> validate_required([:api_id, :version_number, :code, :source])
    |> validate_inclusion(:source, @valid_sources)
    |> validate_inclusion(:compilation_status, @valid_compilation_statuses)
    |> unique_constraint([:api_id, :version_number])
    |> foreign_key_constraint(:created_by_id)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
end
