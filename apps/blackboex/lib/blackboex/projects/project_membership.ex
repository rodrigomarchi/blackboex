defmodule Blackboex.Projects.ProjectMembership do
  @moduledoc """
  Schema for project memberships. Users can have different roles in different projects.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_memberships" do
    field :role, Ecto.Enum, values: [:admin, :editor, :viewer]

    belongs_to :project, Blackboex.Projects.Project
    belongs_to :user, Blackboex.Accounts.User, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(project_membership, attrs) do
    project_membership
    |> cast(attrs, [:project_id, :user_id, :role])
    |> validate_required([:project_id, :user_id, :role])
    |> unique_constraint(:user_id, name: :project_memberships_project_id_user_id_index)
  end

  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(struct, attrs, _metadata) do
    changeset(struct, attrs)
  end
end
