defmodule Blackboex.Projects.Project do
  @moduledoc """
  Schema for projects. Projects group APIs, Flows, and other resources
  within an Organization.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :member_count, :integer, virtual: true

    belongs_to :organization, Blackboex.Organizations.Organization

    has_many :project_memberships, Blackboex.Projects.ProjectMembership

    has_many :users, through: [:project_memberships, :user]

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug, :description, :organization_id])
    |> validate_required([:name, :organization_id])
    |> maybe_generate_slug()
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:slug, name: :projects_organization_id_slug_index)
  end

  @doc """
  Update changeset for projects. Slug is immutable after creation.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(project, attrs, _metadata) do
    project
    |> cast(attrs, [:name, :description, :organization_id])
    |> validate_required([:name, :organization_id])
  end

  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, generate_slug(name))
        end

      _slug ->
        changeset
    end
  end

  defp generate_slug(name) do
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
