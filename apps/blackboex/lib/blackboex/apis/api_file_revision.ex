defmodule Blackboex.Apis.ApiFileRevision do
  @moduledoc """
  Schema for file revisions. Each edit to an ApiFile creates a new revision.

  Revisions are append-only and store the full content snapshot plus a unified diff
  against the previous revision. This enables both time-travel and diff viewing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_sources ~w(generation chat_edit manual_edit rollback)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_file_revisions" do
    field :content, :string
    field :diff, :string
    field :message, :string
    field :source, :string
    field :revision_number, :integer

    belongs_to :api_file, Blackboex.Apis.ApiFile
    belongs_to :created_by, Blackboex.Accounts.User, type: :id

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [
      :api_file_id,
      :content,
      :diff,
      :message,
      :source,
      :revision_number,
      :created_by_id
    ])
    |> validate_required([:api_file_id, :content, :source, :revision_number])
    |> validate_inclusion(:source, @valid_sources)
    |> validate_length(:message, max: 500)
    |> unique_constraint([:api_file_id, :revision_number])
    |> foreign_key_constraint(:created_by_id)
  end
end
