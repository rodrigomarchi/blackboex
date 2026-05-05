defmodule BlackboexWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use BlackboexWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint BlackboexWeb.Endpoint

      use BlackboexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import BlackboexWeb.ConnCase
      import BlackboexWeb.LiveViewHelpers
      import Blackboex.AccountsFixtures
      import Blackboex.OrganizationsFixtures
      import Blackboex.ApisFixtures
      import Blackboex.ConversationsFixtures
      import Blackboex.TestingFixtures
      import Blackboex.ApiFilesFixtures
      import Blackboex.ProjectsFixtures
      import Blackboex.FlowsFixtures
      import Blackboex.FlowExecutionsFixtures
      import Blackboex.PagesFixtures
      import Blackboex.PlaygroundsFixtures
      import Blackboex.PlaygroundExecutionsFixtures
      import Blackboex.PlaygroundConversationsFixtures
      import Blackboex.PageConversationsFixtures
      import Blackboex.PlansFixtures
      import Blackboex.ProjectConversationsFixtures
      import Blackboex.LlmFixtures
      import Blackboex.ProjectEnvVarsFixtures
      import Blackboex.InstanceSettingsFixtures
      import Blackboex.OrgInvitationsFixtures
      import Blackboex.MockDefaults
    end
  end

  setup tags do
    Blackboex.DataCase.setup_sandbox(tags)
    # Pre-populate the Settings first-run cache so existing LiveView tests
    # do not redirect to /setup. The require_setup_test overrides this in
    # its own setup. We deliberately do NOT register an on_exit reset:
    # `:persistent_term` is global and ExUnit runs many test modules
    # concurrently, so an on_exit clear races with other modules' setups.
    # Leaving it as `true` is safe — only require_setup_test cares about
    # the false branch and it sets it explicitly.
    :persistent_term.put({Blackboex.Settings, :setup_completed?}, true)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    alias Blackboex.Accounts.Scope
    alias Blackboex.AccountsFixtures

    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = Blackboex.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    Blackboex.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
