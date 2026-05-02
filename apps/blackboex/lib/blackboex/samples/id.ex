defmodule Blackboex.Samples.Id do
  @moduledoc """
  Stable sample identity helpers.

  Sample UUIDs are derived from the logical `{kind, id}` pair. This keeps the
  identity stable across installs without maintaining a parallel UUID table.
  """

  @namespace "blackboex-sample"

  @spec uuid(atom(), String.t()) :: Ecto.UUID.t()
  def uuid(kind, id) when is_atom(kind) and is_binary(id) do
    <<a::32, b::16, c::16, d::16, e::48>> =
      :crypto.hash(:md5, "#{@namespace}:#{kind}:#{id}")

    "#{hex(a, 8)}-#{hex(b, 4)}-#{hex(c, 4)}-#{hex(d, 4)}-#{hex(e, 12)}"
  end

  defp hex(value, size) do
    value
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(size, "0")
  end
end
