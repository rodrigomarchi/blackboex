defmodule Blackboex.Settings.InstanceSetting do
  @moduledoc """
  Singleton schema for instance-wide settings captured during first-run setup.

  Only one row may exist (id = 1, enforced by a CHECK constraint).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}
  schema "instance_settings" do
    field :app_name, :string
    field :public_url, :string
    field :setup_completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:app_name, :public_url, :setup_completed_at])
    |> validate_required([:app_name, :public_url, :setup_completed_at])
    |> validate_format(:public_url, ~r{^https?://}, message: "must be a valid http(s) URL")
    |> validate_length(:app_name, min: 1, max: 200)
  end
end
