defmodule Blackboex.Apis.Api do
  @moduledoc """
  Schema for APIs. Each API belongs to an organization and a user.
  """

  use Ecto.Schema
  import Ecto.Changeset

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
    field :source_code, :string
    field :template_type, :string, default: "computation"
    field :status, :string, default: "draft"
    field :method, :string, default: "POST"
    field :param_schema, :map
    field :example_request, :map
    field :example_response, :map
    field :visibility, :string, default: "private"
    field :requires_auth, :boolean, default: true

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :user, Blackboex.Accounts.User, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(api, attrs) do
    api
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :source_code,
      :template_type,
      :status,
      :method,
      :param_schema,
      :example_request,
      :example_response,
      :visibility,
      :requires_auth,
      :organization_id,
      :user_id
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 10_000)
    |> maybe_generate_slug()
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
    |> unique_constraint([:organization_id, :slug])
  end

  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, slugify(name))
        end

      _slug ->
        changeset
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s]+/, "-")
    |> String.trim("-")
  end
end
