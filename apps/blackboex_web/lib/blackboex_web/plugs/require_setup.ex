defmodule BlackboexWeb.Plugs.RequireSetup do
  @moduledoc """
  Redirects to `/setup` when the instance has not completed first-run setup.
  Once setup is complete, returns 404 for the wizard path `/setup` itself.

  `/setup/finish` is intentionally NOT 404'd post-completion: it is the
  controller hop that consumes the one-time `SetupTokens` token issued by
  `SetupLive` to log the just-created admin in. The token's 60-second TTL
  and single-use semantics are the security gate, not URL gating.

  Pass-through prefixes (always allowed): `/setup`, `/api`, `/p`, `/webhook`,
  `/assets`, `/dev`. Only mounted on the `:browser` pipeline.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Blackboex.Settings

  @passthrough_prefixes ~w(/api /p /webhook /assets /dev)
  @setup_prefix "/setup"

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case {Settings.setup_completed?(), conn.request_path} do
      {true, @setup_prefix} ->
        conn |> send_resp(404, "") |> halt()

      {true, _} ->
        conn

      {false, path} ->
        if setup_path?(path) or passthrough?(path) do
          conn
        else
          conn |> redirect(to: @setup_prefix) |> halt()
        end
    end
  end

  defp setup_path?(path),
    do: path == @setup_prefix or String.starts_with?(path, @setup_prefix <> "/")

  defp passthrough?(path),
    do: Enum.any?(@passthrough_prefixes, &(path == &1 or String.starts_with?(path, &1 <> "/")))
end
