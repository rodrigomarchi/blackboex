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

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :user, Blackboex.Accounts.User, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [:name, :slug, :description, :status, :definition, :organization_id, :user_id])
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
    |> validate_inclusion(:status, @valid_statuses)
    |> maybe_generate_webhook_token()
    |> unique_constraint([:organization_id, :slug])
    |> unique_constraint(:webhook_token)
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
