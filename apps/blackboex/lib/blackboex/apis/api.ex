defmodule Blackboex.Apis.Api do
  @moduledoc """
  Schema for APIs. Each API belongs to an organization and a user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  import Blackboex.ChangesetHelpers, only: [validate_json_size: 2]

  @type t :: %__MODULE__{}

  @valid_template_types ~w(computation crud webhook)
  @valid_methods ~w(GET POST PUT PATCH DELETE)
  @valid_statuses ~w(draft compiled published archived)
  @valid_visibilities ~w(private public)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "apis" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :template_type, :string, default: "computation"
    field :status, :string, default: "draft"
    field :method, :string, default: "POST"
    field :param_schema, :map
    field :example_request, :map
    field :example_response, :map
    field :visibility, :string, default: "private"
    field :requires_auth, :boolean, default: false
    field :documentation_md, :string
    field :generation_status, :string
    field :generation_error, :string
    field :validation_report, :map
    field :template_id, :string
    field :sample_uuid, Ecto.UUID
    field :sample_manifest_version, :string

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project
    belongs_to :user, Blackboex.Accounts.User, type: :id

    has_many :files, Blackboex.Apis.ApiFile
    has_one :conversation, Blackboex.Conversations.Conversation

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(api, attrs) do
    api
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :template_type,
      :status,
      :method,
      :param_schema,
      :example_request,
      :example_response,
      :visibility,
      :requires_auth,
      :documentation_md,
      :generation_status,
      :generation_error,
      :validation_report,
      :template_id,
      :sample_uuid,
      :sample_manifest_version,
      :organization_id,
      :project_id,
      :user_id
    ])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 10_000)
    |> maybe_generate_slug_with_hash()
    |> validate_required([:slug])
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
      message:
        "must contain only lowercase letters, numbers, and hyphens, and not start/end with a hyphen"
    )
    |> validate_inclusion(:template_type, @valid_template_types)
    |> validate_inclusion(:method, @valid_methods)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> validate_json_size(:param_schema)
    |> validate_json_size(:example_request)
    |> validate_json_size(:example_response)
    |> unique_constraint([:project_id, :slug])
  end

  @doc """
  Update changeset. Slug is immutable after creation.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(api, attrs) do
    api
    |> cast(attrs, [
      :name,
      :description,
      :template_type,
      :status,
      :method,
      :param_schema,
      :example_request,
      :example_response,
      :visibility,
      :requires_auth,
      :documentation_md,
      :generation_status,
      :generation_error,
      :validation_report,
      :template_id,
      :sample_uuid,
      :sample_manifest_version
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 10_000)
    |> validate_inclusion(:template_type, @valid_template_types)
    |> validate_inclusion(:method, @valid_methods)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> validate_json_size(:param_schema)
    |> validate_json_size(:example_request)
    |> validate_json_size(:example_response)
  end

  @doc """
  Changeset for moving an API to a different project (same org).
  Only allows `:project_id` to change.
  """
  @spec move_project_changeset(t(), map()) :: Ecto.Changeset.t()
  def move_project_changeset(api, attrs) do
    api
    |> cast(attrs, [:project_id])
    |> validate_required([:project_id])
  end

  @doc """
  Admin changeset for Backpex admin panel operations.
  """
  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(api, attrs, _metadata) do
    changeset(api, attrs)
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
