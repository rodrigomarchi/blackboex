defmodule Blackboex.ChangesetHelpers do
  @moduledoc """
  Shared changeset validation helpers for the Blackboex domain.
  """

  import Ecto.Changeset

  @default_max_json_bytes 100_000

  @doc """
  Validates that a map/JSONB field's serialized size does not exceed `max_bytes`.

  Only runs the check when the field has been changed and the value is a map or list.
  Defaults to #{@default_max_json_bytes} bytes (100 KB).
  """
  @spec validate_json_size(Ecto.Changeset.t(), atom(), non_neg_integer()) :: Ecto.Changeset.t()
  def validate_json_size(changeset, field, max_bytes \\ @default_max_json_bytes) do
    validate_change(changeset, field, fn _field, value ->
      case json_byte_size(value) do
        {:ok, size} when size > max_bytes ->
          max_kb = div(max_bytes, 1000)
          [{field, "serialized JSON exceeds maximum size of #{max_kb} KB"}]

        {:ok, _size} ->
          []

        :skip ->
          []
      end
    end)
  end

  @spec json_byte_size(term()) :: {:ok, non_neg_integer()} | :skip
  defp json_byte_size(value) when is_map(value) or is_list(value) do
    {:ok, value |> Jason.encode!() |> byte_size()}
  rescue
    _ -> :skip
  end

  defp json_byte_size(_value), do: :skip
end
