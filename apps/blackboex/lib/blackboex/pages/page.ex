defmodule Blackboex.Pages.Page do
  @moduledoc """
  Schema for Pages. Each page belongs to a project and an organization.
  Stores free-form Markdown content for planning, documentation, and notes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(draft published)
  @max_content_length 1_048_576

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pages" do
    field :title, :string
    field :slug, :string
    field :content, :string, default: ""
    field :status, :string, default: "draft"

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project
    belongs_to :user, Blackboex.Accounts.User, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :slug, :content, :status, :organization_id, :project_id, :user_id])
    |> validate_required([:title, :project_id, :organization_id, :user_id])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:content, max: @max_content_length)
    |> maybe_generate_slug_with_hash()
    |> validate_required([:slug])
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
      message:
        "must contain only lowercase letters, numbers, and hyphens, and not start/end with a hyphen"
    )
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:project_id, :slug], error_key: :slug)
  end

  @doc """
  Update changeset for pages. Slug is immutable after creation.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :content, :status])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:content, max: @max_content_length)
    |> validate_inclusion(:status, @valid_statuses)
  end

  defp maybe_generate_slug_with_hash(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :title) do
          nil -> changeset
          title -> put_change(changeset, :slug, generate_slug_with_hash(title))
        end

      _slug ->
        changeset
    end
  end

  defp generate_slug_with_hash(title) do
    base =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/[\s]+/, "-")
      |> String.trim("-")

    hash = Nanoid.generate(6, "abcdefghijklmnopqrstuvwxyz0123456789")
    "#{base}-#{hash}"
  end
end
