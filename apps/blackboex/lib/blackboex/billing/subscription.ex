defmodule Blackboex.Billing.Subscription do
  @moduledoc """
  Schema for organization billing subscriptions.
  Tracks Stripe subscription state locally.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Blackboex.Organizations.Organization

  @type t :: %__MODULE__{}

  @valid_plans ~w(free pro enterprise)
  @valid_statuses ~w(active past_due canceled trialing)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "subscriptions" do
    belongs_to :organization, Organization
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :plan, :string, default: "free"
    field :status, :string, default: "active"
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false

    timestamps()
  end

  @doc """
  Admin changeset for Backpex admin panel.
  """
  @spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
  def admin_changeset(subscription, attrs, _metadata) do
    changeset(subscription, attrs)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :organization_id,
      :stripe_customer_id,
      :stripe_subscription_id,
      :plan,
      :status,
      :current_period_start,
      :current_period_end,
      :cancel_at_period_end
    ])
    |> validate_required([:organization_id, :plan, :status])
    |> validate_inclusion(:plan, @valid_plans)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:stripe_customer_id, max: 255)
    |> validate_length(:stripe_subscription_id, max: 255)
    |> unique_constraint(:organization_id)
    |> foreign_key_constraint(:organization_id)
  end
end
