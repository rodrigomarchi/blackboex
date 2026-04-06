defmodule Blackboex.ApisFixtures do
  @moduledoc """
  Test helpers for creating API entities.
  """

  alias Blackboex.Apis
  alias Blackboex.Apis.{ApiKey, InvocationLog, MetricRollup}
  alias Blackboex.Repo

  @doc """
  Creates an API for the given user and organization.

  ## Options

    * `:user` - the owner user (required, or provide via `:user` + `:org`)
    * `:org` - the organization (required, or auto-created with user)
    * `:name` - API name (default: auto-generated)
    * `:template_type` - template type (default: "computation")
    * Any additional attrs are passed through to `Apis.create_api/1`

  Returns the API struct.
  """
  @spec api_fixture(map()) :: Blackboex.Apis.Api.t()
  def api_fixture(attrs \\ %{}) do
    {user, org} =
      case {attrs[:user], attrs[:org]} do
        {nil, nil} ->
          Blackboex.OrganizationsFixtures.user_and_org_fixture()

        {user, nil} ->
          {user, Blackboex.OrganizationsFixtures.org_fixture(%{user: user})}

        {nil, org} ->
          {Blackboex.AccountsFixtures.user_fixture(), org}

        {user, org} ->
          {user, org}
      end

    known_keys = [:user, :org, :name, :template_type]
    extra = Map.drop(attrs, known_keys)

    {:ok, api} =
      Apis.create_api(
        Map.merge(
          %{
            name: attrs[:name] || "Test API #{System.unique_integer([:positive])}",
            template_type: attrs[:template_type] || "computation",
            organization_id: org.id,
            user_id: user.id
          },
          extra
        )
      )

    api
  end

  @doc """
  Named setup: creates an API for existing user + org in context.

  Requires `:user` and `:org` in context.

  Usage: `setup [:register_and_log_in_user, :create_org, :create_api]`
  """
  @spec create_api(map()) :: map()
  def create_api(%{user: user, org: org}) do
    api = api_fixture(%{user: user, org: org})
    %{api: api}
  end

  @doc """
  Named setup: creates org + API for existing user in context.

  Requires `:user` in context (e.g. from `register_and_log_in_user`).

  Usage: `setup [:register_and_log_in_user, :create_org_and_api]`
  """
  @spec create_org_and_api(map()) :: map()
  def create_org_and_api(%{user: user}) do
    org = Blackboex.OrganizationsFixtures.org_fixture(%{user: user})
    api = api_fixture(%{user: user, org: org})
    %{org: org, api: api}
  end

  @doc """
  Creates an API key for the given API.

  Returns `{plain_key, api_key}` tuple.
  """
  @spec api_key_fixture(Blackboex.Apis.Api.t(), map()) :: {String.t(), ApiKey.t()}
  def api_key_fixture(api, attrs \\ %{}) do
    {:ok, plain_key, api_key} =
      Apis.Keys.create_key(
        api,
        Map.merge(%{label: "Test Key", organization_id: api.organization_id}, attrs)
      )

    {plain_key, api_key}
  end

  @doc """
  Inserts an invocation log for the given API.

  ## Required

    * `:api_id` - the API ID

  ## Optional

    * `:method` - HTTP method (default: "POST")
    * `:path` - request path (default: "/api/test")
    * `:status_code` - HTTP status (default: 200)
    * `:duration_ms` - duration in ms (default: 50)
    * `:ip_address` - client IP (default: "127.0.0.1")
    * Any other InvocationLog fields

  Returns the invocation log struct.
  """
  @spec invocation_log_fixture(map()) :: InvocationLog.t()
  def invocation_log_fixture(attrs) do
    %InvocationLog{}
    |> InvocationLog.changeset(
      Map.merge(
        %{
          method: "POST",
          path: "/api/test",
          status_code: 200,
          duration_ms: 50,
          request_body_size: 0,
          response_body_size: 100,
          ip_address: "127.0.0.1"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc """
  Inserts a metric rollup for the given API.

  ## Required

    * `:api_id` - the API ID
    * `:date` - the date
    * `:hour` - the hour (0-23)

  ## Optional

    * `:invocations` - total invocations (default: 0)
    * `:errors` - error count (default: 0)
    * `:unique_consumers` - unique consumer count (default: 0)
    * `:avg_duration_ms` - average duration (default: 0.0)
    * `:p95_duration_ms` - p95 duration (default: 0.0)

  Returns the metric rollup struct.
  """
  @spec metric_rollup_fixture(map()) :: MetricRollup.t()
  def metric_rollup_fixture(attrs) do
    %MetricRollup{}
    |> MetricRollup.changeset(
      Map.merge(
        %{
          invocations: 0,
          errors: 0,
          unique_consumers: 0,
          avg_duration_ms: 0.0,
          p95_duration_ms: 0.0
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
