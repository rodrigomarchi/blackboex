defmodule BlackboexWeb.Plugs.Authorize do
  @moduledoc """
  Plug that checks authorization using `Blackboex.Policy`.
  Expects `:current_scope` and `:authorization_object` to be set in assigns.
  """

  import Plug.Conn

  alias Blackboex.Policy

  @behaviour Plug

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    scope = conn.assigns[:current_scope]
    object = conn.assigns[:authorization_object]

    if Policy.authorize?(action, scope, object) do
      conn
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end
end
