defmodule Blackboex.ProjectEnvVars.ProjectEnvVar do
  @moduledoc """
  Schema for ProjectEnvVars. Stores encrypted (Base64-encoded) env var values
  scoped to a project, with a `kind` discriminator separating generic env vars
  from special integrations (currently just the Anthropic API key).

  Note: "encryption" is Base64 encoding for MVP — placeholder for Cloak later.
  """

  use Blackboex.Schema

  @type t :: %__MODULE__{}

  @kinds ~w(env llm_anthropic)
  @name_max_length 255
  # Generic env vars are limited to 8KiB; llm_anthropic keys can be up to 16KiB
  # (Anthropic API keys are long, future providers may be longer).
  @value_max_length_env 8_192
  @value_max_length_llm 16_384

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_env_vars" do
    field :name, :string
    field :encrypted_value, :binary
    field :kind, :string, default: "env"

    belongs_to :organization, Blackboex.Organizations.Organization
    belongs_to :project, Blackboex.Projects.Project

    timestamps()
  end

  @doc """
  Changeset for create + update. Pass `value` (plaintext) in attrs — it is
  encoded into `encrypted_value` via `maybe_encrypt_value/2`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(env_var, attrs) do
    env_var
    |> cast(attrs, [:name, :organization_id, :project_id, :kind])
    |> validate_required([:name, :organization_id, :project_id])
    |> validate_format(:name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/,
      message:
        "must start with a letter or underscore and contain only letters, digits, and underscores"
    )
    |> validate_length(:name, max: @name_max_length)
    |> validate_inclusion(:kind, @kinds)
    |> validate_value_length(attrs)
    |> maybe_encrypt_value(attrs)
    |> validate_required([:encrypted_value])
    |> unique_constraint([:project_id, :kind, :name])
    |> unique_constraint(:project_id,
      name: :project_env_vars_unique_llm_per_project_idx,
      message: "already has an LLM key configured"
    )
  end

  @doc "Encodes a plaintext value into the opaque storage representation."
  @spec encrypt_value(String.t()) :: binary()
  def encrypt_value(plaintext) do
    Base.encode64(plaintext)
  end

  @doc "Decodes the opaque storage representation back to plaintext."
  @spec decrypt_value(binary()) :: String.t()
  def decrypt_value(encrypted) do
    Base.decode64!(encrypted)
  end

  @doc "Returns the list of valid `kind` values."
  @spec valid_kinds() :: [String.t()]
  def valid_kinds, do: @kinds

  defp maybe_encrypt_value(changeset, attrs) do
    value = attrs[:value] || attrs["value"]

    case value do
      nil -> changeset
      v when is_binary(v) -> put_change(changeset, :encrypted_value, encrypt_value(v))
      _ -> add_error(changeset, :value, "must be a string")
    end
  end

  defp validate_value_length(changeset, attrs) do
    value = attrs[:value] || attrs["value"]
    kind = get_field(changeset, :kind) || "env"

    if is_binary(value) do
      apply_value_checks(changeset, value, kind)
    else
      changeset
    end
  end

  defp apply_value_checks(changeset, "", _kind) do
    add_error(changeset, :value, "can't be blank")
  end

  defp apply_value_checks(changeset, value, kind) do
    max = value_max_length(kind)

    cond do
      byte_size(value) > max -> add_too_long_error(changeset, max)
      has_embedded_control_chars?(value) -> add_control_chars_error(changeset)
      true -> changeset
    end
  end

  defp add_too_long_error(changeset, max) do
    add_error(
      changeset,
      :value,
      "should be at most %{count} byte(s)",
      count: max,
      validation: :length,
      kind: :max,
      type: :bytes
    )
  end

  defp add_control_chars_error(changeset) do
    add_error(changeset, :value, "must not contain NUL, CR or LF characters")
  end

  defp value_max_length("llm_anthropic"), do: @value_max_length_llm
  defp value_max_length(_), do: @value_max_length_env

  # Reject NUL/CR/LF embedded in any project env var value — these are
  # header-injection vectors and have no legitimate use in a single-line
  # env var or API key.
  @spec has_embedded_control_chars?(binary()) :: boolean()
  defp has_embedded_control_chars?(value) when is_binary(value) do
    String.contains?(value, ["\0", "\r", "\n"])
  end
end
