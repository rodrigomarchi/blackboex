defmodule BlackboexWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Custom body reader that caches the raw request body.
  Required for Stripe webhook signature verification,
  which needs the original raw body before JSON parsing.
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:more, body, conn}
    end
  end

  @spec get_raw_body(Plug.Conn.t()) :: String.t()
  def get_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> ""
      list when is_list(list) -> list |> Enum.reverse() |> Enum.join()
      binary when is_binary(binary) -> binary
    end
  end
end
