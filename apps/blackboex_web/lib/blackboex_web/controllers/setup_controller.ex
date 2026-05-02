defmodule BlackboexWeb.SetupController do
  @moduledoc """
  Bridges the setup wizard (LiveView) to a session-bearing controller
  response. Consumes a one-time token issued by `BlackboexWeb.SetupTokens`
  and logs the resulting user in via `BlackboexWeb.UserAuth.log_in_user/3`.
  """
  use BlackboexWeb, :controller

  alias Blackboex.Accounts
  alias BlackboexWeb.SetupTokens
  alias BlackboexWeb.UserAuth

  @spec finish(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def finish(conn, %{"token" => token}) do
    with {:ok, user_id} <- SetupTokens.consume(token),
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      UserAuth.log_in_user(conn, user, %{})
    else
      _ -> reject(conn)
    end
  end

  def finish(conn, _params), do: reject(conn)

  defp reject(conn) do
    conn
    |> put_flash(:error, "Setup link expired or invalid. Please log in.")
    |> redirect(to: ~p"/users/log-in")
  end
end
