defmodule Blackboex.Playgrounds.Playground do
  @moduledoc """
  Schema for Playgrounds. Each playground belongs to a project and an organization.
  Stores a single code cell for interactive Elixir experimentation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @max_code_length 262_144

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "playgrounds" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :code, :string, default: ""
    field :last_output, :string

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project
    belongs_to :user, Blackboex.Accounts.User, type: :id

    has_many :executions, Blackboex.Playgrounds.PlaygroundExecution

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(playground, attrs) do
    playground
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :code,
      :last_output,
      :organization_id,
      :project_id,
      :user_id
    ])
    |> validate_required([:name, :project_id, :organization_id, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:code, max: @max_code_length)
    |> maybe_generate_slug_with_hash()
    |> validate_required([:slug])
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
      message:
        "must contain only lowercase letters, numbers, and hyphens, and not start/end with a hyphen"
    )
    |> unique_constraint([:project_id, :slug], error_key: :slug)
  end

  @doc """
  Update changeset for playgrounds. Slug is immutable after creation.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(playground, attrs) do
    playground
    |> cast(attrs, [:name, :description, :code, :last_output])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:code, max: @max_code_length)
    |> validate_length(:last_output, max: 65_536)
  end

  @doc """
  Changeset for moving a Playground to a different project (same org).
  Only allows `:project_id` to change.
  """
  @spec move_project_changeset(t(), map()) :: Ecto.Changeset.t()
  def move_project_changeset(playground, attrs) do
    playground
    |> cast(attrs, [:project_id])
    |> validate_required([:project_id])
  end

  defp maybe_generate_slug_with_hash(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, generate_slug_with_hash(name))
        end

      _slug ->
        changeset
    end
  end

  defp generate_slug_with_hash(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/[\s]+/, "-")
      |> String.trim("-")

    hash = Nanoid.generate(6, "abcdefghijklmnopqrstuvwxyz0123456789")
    "#{base}-#{hash}"
  end
end
