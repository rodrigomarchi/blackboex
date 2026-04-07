defmodule Blackboex.Apis.ApiFile do
  @moduledoc """
  Schema for files within an API project.

  Each API has a virtual filesystem with source and test files.
  Files track their current content and type for compilation/testing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_file_types ~w(source test config doc)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_files" do
    field :path, :string
    field :content, :string
    field :file_type, :string

    belongs_to :api, Blackboex.Apis.Api
    has_many :revisions, Blackboex.Apis.ApiFileRevision

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:api_id, :path, :content, :file_type])
    |> validate_required([:api_id, :path, :file_type])
    |> validate_inclusion(:file_type, @valid_file_types)
    |> validate_format(:path, ~r{^/[a-zA-Z0-9_/.-]+\.(ex|md)$},
      message: "must start with / and end with .ex or .md (e.g. /src/handler.ex, /README.md)"
    )
    |> unique_constraint([:api_id, :path])
  end
end
