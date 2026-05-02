defmodule Blackboex.Flows.Flow do
  @moduledoc """
  Schema for Flows. Each flow belongs to an organization and a user.
  Stores the visual graph definition as JSONB.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Blackboex.FlowExecutor.BlackboexFlow

  @type t :: %__MODULE__{}

  @valid_statuses ~w(draft active archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "flows" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :definition, :map, default: %{}
    field :webhook_token, :string
    field :sample_uuid, Ecto.UUID
    field :sample_manifest_version, :string

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project
    belongs_to :user, Blackboex.Accounts.User, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :status,
      :definition,
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
    |> validate_inclusion(:status, @valid_statuses)
    |> maybe_generate_webhook_token()
    |> unique_constraint([:project_id, :slug])
    |> unique_constraint(:webhook_token)
  end

  @doc """
  Update changeset for flows. Slug is immutable after creation.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :definition,
      :sample_uuid,
      :sample_manifest_version
    ])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 10_000)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Changeset for moving a Flow to a different project (same org).
  Only allows `:project_id` to change.
  """
  @spec move_project_changeset(t(), map()) :: Ecto.Changeset.t()
  def move_project_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:project_id])
    |> validate_required([:project_id])
  end

  @spec webhook_token_changeset(t()) :: Ecto.Changeset.t()
  def webhook_token_changeset(flow) do
    flow
    |> change(%{webhook_token: generate_webhook_token()})
    |> unique_constraint(:webhook_token)
  end

  @spec definition_changeset(t(), map()) :: Ecto.Changeset.t()
  def definition_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:definition])
    |> validate_required([:definition])
    |> validate_definition_structure()
  end

  defp validate_definition_structure(changeset) do
    case get_change(changeset, :definition) do
      nil ->
        changeset

      definition when definition == %{} ->
        changeset

      definition ->
        case BlackboexFlow.validate(definition) do
          :ok -> changeset
          {:error, reason} -> add_error(changeset, :definition, reason)
        end
    end
  end

  defp maybe_generate_webhook_token(changeset) do
    case get_field(changeset, :webhook_token) do
      nil -> put_change(changeset, :webhook_token, generate_webhook_token())
      _ -> changeset
    end
  end

  defp generate_webhook_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
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
