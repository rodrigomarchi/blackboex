# Discovery: Backoffice, Admin Panel & Configuration System

> Research date: 2026-03-17
> Scope: Admin panel, configuration management, authentication, billing, RBAC, audit logging, and settings UI for BlackBoex.

---

## Table of Contents

1. [Admin Panel Libraries](#1-admin-panel-libraries)
2. [Configuration Management](#2-configuration-management)
3. [User Management & Authentication](#3-user-management--authentication)
4. [Billing & Usage Tracking](#4-billing--usage-tracking)
5. [Role-Based Access Control (RBAC)](#5-role-based-access-control-rbac)
6. [Audit Logging](#6-audit-logging)
7. [Settings UI with LiveView](#7-settings-ui-with-liveview)
8. [Architecture Recommendation for BlackBoex](#8-architecture-recommendation-for-blackboex)

---

## 1. Admin Panel Libraries

### 1.1 Backpex (Recommended)

- **Repo**: https://github.com/naymspace/backpex
- **Hex**: `{:backpex, "~> 0.17"}`
- **Latest**: v0.17.4 (March 2026), 826 stars, actively maintained
- **Stack**: Phoenix LiveView + TailwindCSS + DaisyUI

Backpex is the most mature and actively maintained admin panel for Phoenix LiveView. It generates fully functional index, show, new, and edit views through configurable `LiveResource` modules.

**Key Features:**
- LiveResources with automatic CRUD views
- Built-in search and custom filters
- Resource actions (global) and item actions (per-row)
- Authorization via `can?/3` callback
- Field types: Text, Number, Date, Upload, associations (HasOne, BelongsTo, HasMany/Through)
- Metrics on index view (sums, averages, counts)
- Customizable layouts, panels, and slots
- PubSub support for real-time updates
- Full-text search support
- Pagination with configurable page sizes
- Translatable UI strings

**LiveResource Example:**

```elixir
defmodule BlackBoexWeb.Admin.UserLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: BlackBoex.Accounts.User,
      repo: BlackBoex.Repo,
      update_changeset: &BlackBoex.Accounts.User.admin_changeset/3,
      create_changeset: &BlackBoex.Accounts.User.admin_changeset/3
    ],
    layout: {BlackBoexWeb.Layouts, :admin},
    pubsub: [server: BlackBoex.PubSub, topic: "users"]

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def fields do
    [
      email: %{module: Backpex.Fields.Text, label: "Email", searchable: true},
      role: %{module: Backpex.Fields.Text, label: "Role"},
      confirmed_at: %{module: Backpex.Fields.DateTime, label: "Confirmed", only: [:index, :show]},
      inserted_at: %{module: Backpex.Fields.DateTime, label: "Created", only: [:index, :show]}
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, :index, _item), do: assigns.current_user.role == :admin
  def can?(assigns, :show, _item), do: assigns.current_user.role == :admin
  def can?(assigns, :edit, _item), do: assigns.current_user.role == :admin
  def can?(assigns, :delete, _item), do: assigns.current_user.role == :superadmin
  def can?(_assigns, _action, _item), do: false
end
```

**Callbacks Available:**
- `fields/0` — define resource fields (required)
- `singular_name/0`, `plural_name/0` — display names (required)
- `can?/3` — authorization per action (required)
- `filters/0`, `filters/1` — custom filters
- `resource_actions/0` — global actions (e.g., export, invite)
- `item_actions/1` — per-item actions
- `panels/0` — group fields into sections
- `metrics/0` — index-view metrics
- `on_item_created/2`, `on_item_updated/2`, `on_item_deleted/2` — lifecycle hooks
- `render_resource_slot/3` — inject content at specific positions
- `translate/1` — custom translations

### 1.2 Kaffy

- **Repo**: https://github.com/aesmail/kaffy
- **Hex**: `{:kaffy, "~> 0.10"}`
- **Inspiration**: Django Admin, Rails ActiveAdmin

Kaffy is a simpler, convention-based admin that auto-detects Ecto schemas and generates CRUD pages with minimal configuration. Good for quick prototyping but less customizable than Backpex.

**Features:**
- Auto-detection of schemas and admin modules
- Dashboard with widgets (text, tidbit, progress, chart)
- Custom static pages
- Scheduled tasks
- CSS/JS extensions
- Only depends on Phoenix and Ecto

**Limitations:**
- Less actively maintained than Backpex
- Not built on LiveView (uses traditional controllers)
- Fewer customization hooks
- No built-in authorization system

### 1.3 Ash Admin

- **Repo**: https://github.com/ash-project/ash_admin
- **Hex**: `{:ash_admin, "~> 0.13"}`
- **Requires**: Ash Framework

A super-admin UI dashboard for Ash Framework applications, built with Phoenix LiveView. Only viable if the project adopts Ash Framework for the domain layer.

**Verdict**: Not recommended for BlackBoex since we use standard Phoenix/Ecto contexts.

### 1.4 Comparison Matrix

| Feature              | Backpex          | Kaffy           | Ash Admin       |
|----------------------|------------------|-----------------|-----------------|
| LiveView-native      | Yes              | No              | Yes             |
| Active maintenance   | Very active      | Moderate        | Active          |
| Auto-detection       | No (explicit)    | Yes             | Yes (Ash)       |
| Authorization        | Built-in can?/3  | None built-in   | Ash policies    |
| Custom fields        | Yes              | Limited         | Yes             |
| Search/Filters       | Built-in         | Basic           | Built-in        |
| Resource actions     | Yes              | No              | Yes             |
| Metrics              | Yes              | Dashboard only  | No              |
| Styling              | Tailwind+DaisyUI | Bootstrap       | Tailwind        |
| Framework dependency | Phoenix+Ecto     | Phoenix+Ecto    | Ash Framework   |

**Recommendation: Backpex** — most feature-rich, actively maintained, LiveView-native, and works with standard Phoenix/Ecto patterns.

---

## 2. Configuration Management

### 2.1 Feature Flags with FunWithFlags

- **Repo**: https://github.com/tompave/fun_with_flags
- **Hex**: `{:fun_with_flags, "~> 1.13"}`
- **Downloads**: ~224k weekly (March 2025)

FunWithFlags is the de-facto standard for feature flags in Elixir. It provides a 2-level storage architecture with ETS cache for fast reads and persistent storage (PostgreSQL via Ecto or Redis) for durability.

**Five Gate Types:**

1. **Boolean** — globally enable/disable
2. **Actor** — per-entity targeting (e.g., specific user)
3. **Group** — category-based targeting (e.g., "beta_users")
4. **Percentage-of-Time** — random probabilistic enabling
5. **Percentage-of-Actors** — deterministic actor-based rollout

**Gate priority**: Actor > Group > Boolean > Percentage

**Configuration:**

```elixir
# config/config.exs
config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Persistence.Ecto,
  repo: BlackBoex.Repo

config :fun_with_flags, :pubsub,
  adapter: FunWithFlags.PubSub.Phoenix,
  pubsub: BlackBoex.PubSub

# Optional: cache TTL (default 900s)
config :fun_with_flags, :cache, ttl: 900
```

**Usage in BlackBoex:**

```elixir
# Global feature flag
FunWithFlags.enable(:code_generation_v2)

# Enable for specific user (Actor gate)
defimpl FunWithFlags.Actor, for: BlackBoex.Accounts.User do
  def id(%{id: id}), do: "user:#{id}"
end

FunWithFlags.enable(:code_generation_v2, for_actor: user)

# Enable for a percentage of users (gradual rollout)
FunWithFlags.enable(:new_editor, for_percentage_of: {:actors, 0.25})

# Group gate for organizations
defimpl FunWithFlags.Group, for: BlackBoex.Accounts.User do
  def in?(%{plan: plan}, "pro"), do: plan in [:pro, :enterprise]
  def in?(%{plan: :enterprise}, "enterprise"), do: true
  def in?(_, _), do: false
end

FunWithFlags.enable(:custom_domains, for_group: "enterprise")

# Check in LiveView or context
if FunWithFlags.enabled?(:code_generation_v2, for: current_user) do
  CodeGen.V2.generate(spec)
else
  CodeGen.V1.generate(spec)
end
```

**Web Dashboard**: `fun_with_flags_ui` provides a Plug-based control panel:

```elixir
# config/config.exs
config :fun_with_flags, :flag_management_ui,
  adapter: FunWithFlags.UI.Router

# router.ex
forward "/admin/feature-flags", FunWithFlags.UI.Router, namespace: "admin"
```

### 2.2 Runtime Configuration for API Keys

For per-user/org LLM API keys, use a combination of encrypted database storage and an ETS-backed cache.

**Encrypted Storage with Cloak:**

```elixir
# Cloak Vault
defmodule BlackBoex.Vault do
  use Cloak.Vault, otp_app: :blackboex
end

# config/runtime.exs
config :blackboex, BlackBoex.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!(System.fetch_env!("CLOAK_KEY")),
      iv_length: 12}
  ]

# Encrypted Ecto type
defmodule BlackBoex.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: BlackBoex.Vault
end
```

**API Keys Schema:**

```elixir
defmodule BlackBoex.Settings.LlmApiKey do
  use Ecto.Schema

  schema "llm_api_keys" do
    field :provider, Ecto.Enum, values: [:openai, :anthropic, :google, :custom]
    field :api_key, BlackBoex.Encrypted.Binary
    field :api_key_hash, :string  # For lookup without decryption
    field :label, :string
    field :is_active, :boolean, default: true

    belongs_to :user, BlackBoex.Accounts.User
    belongs_to :organization, BlackBoex.Accounts.Organization

    timestamps()
  end
end
```

**ETS-Backed Config Cache:**

```elixir
defmodule BlackBoex.Settings.ConfigCache do
  use GenServer

  @table :config_cache
  @ttl_ms :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @spec get(String.t(), atom()) :: {:ok, term()} | :miss
  def get(user_id, key) do
    case :ets.lookup(@table, {user_id, key}) do
      [{_, value, expires_at}] when expires_at > System.monotonic_time(:millisecond) ->
        {:ok, value}
      _ ->
        :miss
    end
  end

  @spec put(String.t(), atom(), term()) :: :ok
  def put(user_id, key, value) do
    expires_at = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {{user_id, key}, value, expires_at})
    :ok
  end

  @spec invalidate(String.t()) :: :ok
  def invalidate(user_id) do
    :ets.match_delete(@table, {{user_id, :_}, :_, :_})
    :ok
  end
end
```

### 2.3 Rate Limiting

For per-user/per-org rate limits, store limits in the database and enforce them with a token bucket or sliding window in ETS:

```elixir
defmodule BlackBoex.RateLimiter do
  @table :rate_limits

  def init do
    :ets.new(@table, [:named_table, :set, :public, write_concurrency: true])
  end

  @spec check_rate(String.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :rate_limited, retry_after_ms :: pos_integer()}
  def check_rate(key, max_requests, window_ms) do
    now = System.monotonic_time(:millisecond)
    window_start = now - window_ms

    case :ets.lookup(@table, key) do
      [{^key, timestamps}] ->
        recent = Enum.filter(timestamps, &(&1 > window_start))

        if length(recent) < max_requests do
          :ets.insert(@table, {key, [now | recent]})
          :ok
        else
          oldest = Enum.min(recent)
          retry_after = oldest + window_ms - now
          {:error, :rate_limited, retry_after}
        end

      [] ->
        :ets.insert(@table, {key, [now]})
        :ok
    end
  end
end
```

---

## 3. User Management & Authentication

### 3.1 Phoenix 1.8 phx.gen.auth (Magic Links)

Phoenix 1.8 revamped `mix phx.gen.auth` to use **magic link (passwordless) authentication** as the primary flow.

**How it works:**
1. User enters email on registration/login page
2. System sends a magic link via email
3. Clicking the link shows a confirmation form with "Keep me logged in" checkbox
4. On submission, account is confirmed and user is authenticated
5. Users can optionally set a password for traditional login as an alternative

**Key Components Generated:**
- `User` schema with email, optional hashed_password, confirmed_at
- `UserToken` schema for sessions, magic links, and email change tokens
- `Scope` struct for authorization context
- Authentication module with plugs: `fetch_current_scope_for_user`, `require_authenticated_user`, `redirect_if_user_is_authenticated`
- `sudo_mode?/2` — verifies re-authentication within 20 minutes for sensitive operations

**Deployment Note:** Magic links require a transactional email service (e.g., Swoosh + Mailgun/SES/Postmark).

### 3.2 OAuth with Ueberauth

Ueberauth provides the initial OAuth challenge flow and integrates well with `phx.gen.auth`:

```elixir
# mix.exs
{:ueberauth, "~> 0.10"},
{:ueberauth_github, "~> 0.8"},
{:ueberauth_google, "~> 0.12"}

# config/config.exs
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]},
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]
```

**Integration Pattern:**
- Ueberauth handles the OAuth redirect/callback flow
- On callback success, find-or-create the user by email
- Create a session using the same session system from `phx.gen.auth`
- Link OAuth identities to the user account

### 3.3 Multi-Tenancy (Organizations)

For BlackBoex, the **foreign key / row-level approach** is recommended over schema-based isolation, given:
- Simpler implementation and maintenance
- Better query performance for cross-tenant analytics
- Easier to implement in an existing codebase
- Sufficient isolation for a SaaS platform

**Implementation Pattern:**

```elixir
defmodule BlackBoex.Accounts.Organization do
  use Ecto.Schema

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :plan, Ecto.Enum, values: [:free, :pro, :enterprise]

    has_many :memberships, BlackBoex.Accounts.Membership
    has_many :users, through: [:memberships, :user]
    has_many :endpoints, BlackBoex.Endpoints.Endpoint

    timestamps()
  end
end

defmodule BlackBoex.Accounts.Membership do
  use Ecto.Schema

  schema "memberships" do
    field :role, Ecto.Enum, values: [:owner, :admin, :member, :viewer]

    belongs_to :user, BlackBoex.Accounts.User
    belongs_to :organization, BlackBoex.Accounts.Organization

    timestamps()
  end
end
```

**Scoping Queries:**

```elixir
defmodule BlackBoex.Endpoints do
  import Ecto.Query

  def list_endpoints(%Scope{organization: org}) do
    Endpoint
    |> where(organization_id: ^org.id)
    |> Repo.all()
  end
end
```

**Plug for Organization Context:**

```elixir
defmodule BlackBoexWeb.Plugs.SetOrganization do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns.current_user

    case BlackBoex.Accounts.get_current_organization(user) do
      {:ok, org} -> assign(conn, :current_organization, org)
      {:error, _} -> conn |> put_status(403) |> halt()
    end
  end
end
```

---

## 4. Billing & Usage Tracking

### 4.1 Stripe Integration with Stripity Stripe

- **Hex**: `{:stripity_stripe, "~> 3.2"}`
- **API Coverage**: Customer, Subscription, Invoice, Price, PaymentIntent, UsageRecord, PaymentMethod, and more

**Usage-Based Billing Architecture for BlackBoex:**

BlackBoex charges per API request and/or per LLM token consumed. This maps perfectly to Stripe's usage-based billing model.

**Stripe Billing Meters (Modern Approach):**

Stripe's Billing Meters API (V2) allows sending up to 10,000 events/second:

```elixir
defmodule BlackBoex.Billing do
  @doc "Report API call usage to Stripe"
  @spec report_usage(String.t(), pos_integer()) :: :ok | {:error, term()}
  def report_usage(subscription_item_id, quantity) do
    Stripe.UsageRecord.create(subscription_item_id, %{
      quantity: quantity,
      timestamp: DateTime.utc_now() |> DateTime.to_unix(),
      action: "increment"
    })
  end
end
```

### 4.2 Internal Usage Tracking

Track usage locally for real-time dashboards and rate limiting, then sync to Stripe asynchronously.

**Usage Events Schema:**

```elixir
defmodule BlackBoex.Billing.UsageEvent do
  use Ecto.Schema

  schema "usage_events" do
    field :event_type, Ecto.Enum,
      values: [:api_call, :code_generation, :endpoint_deploy]
    field :tokens_input, :integer, default: 0
    field :tokens_output, :integer, default: 0
    field :duration_ms, :integer
    field :metadata, :map, default: %{}

    belongs_to :user, BlackBoex.Accounts.User
    belongs_to :organization, BlackBoex.Accounts.Organization
    belongs_to :endpoint, BlackBoex.Endpoints.Endpoint

    timestamps(updated_at: false)
  end
end
```

**Aggregation with Oban:**

Use Oban scheduled jobs to aggregate usage and report to Stripe:

```elixir
defmodule BlackBoex.Billing.Workers.UsageAggregator do
  use Oban.Worker, queue: :billing, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
    window_start = DateTime.utc_now() |> DateTime.add(-1, :hour)

    usage = BlackBoex.Billing.aggregate_usage(org_id, window_start)

    with {:ok, _} <- BlackBoex.Billing.report_to_stripe(org_id, usage) do
      :ok
    end
  end
end

# Schedule hourly aggregation via Oban cron
config :blackboex, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 * * * *", BlackBoex.Billing.Workers.UsageAggregator}
    ]}
  ]
```

**Daily Usage Summary View:**

```elixir
defmodule BlackBoex.Billing.DailyUsage do
  use Ecto.Schema

  schema "daily_usage" do
    field :date, :date
    field :api_calls, :integer, default: 0
    field :tokens_input, :integer, default: 0
    field :tokens_output, :integer, default: 0
    field :code_generations, :integer, default: 0
    field :estimated_cost_cents, :integer, default: 0

    belongs_to :organization, BlackBoex.Accounts.Organization

    timestamps()
  end
end
```

### 4.3 Billing Architecture Diagram

```
User Request
    |
    v
[API Gateway / Plug] --> [Rate Limiter (ETS)]
    |
    v
[Code Generation Context]
    |
    +---> [Usage Event (insert to DB)]
    |
    +---> [LLM Provider] --> [Track tokens in/out]
    |
    v
[Oban Worker (hourly)]
    |
    +---> Aggregate usage from usage_events
    +---> Report to Stripe via UsageRecord API
    +---> Update daily_usage summary table
```

---

## 5. Role-Based Access Control (RBAC)

### 5.1 Bodyguard

- **Repo**: https://github.com/schrockwell/bodyguard
- **Hex**: `{:bodyguard, "~> 2.4"}`
- **Philosophy**: Authorization lives in context modules (inspired by Pundit)

**Core API:**
- `Bodyguard.permit/4` — returns `:ok` or `{:error, reason}`
- `Bodyguard.permit?/4` — boolean variant
- `Bodyguard.permit!/5` — raises `Bodyguard.NotAuthorizedError`
- `Bodyguard.scope/4` — query scoping per user

**Example:**

```elixir
defmodule BlackBoex.Endpoints do
  @behaviour Bodyguard.Policy

  # Superadmin can do anything
  def authorize(_, %{role: :superadmin}, _), do: true

  # Admin can manage endpoints in their org
  def authorize(:create_endpoint, %{role: :admin, organization_id: org_id}, %{organization_id: org_id}), do: true
  def authorize(:update_endpoint, %{role: :admin, organization_id: org_id}, %{organization_id: org_id}), do: true

  # Members can view endpoints
  def authorize(:list_endpoints, %{organization_id: org_id}, %{organization_id: org_id}), do: true
  def authorize(:show_endpoint, %{organization_id: org_id}, %{organization_id: org_id}), do: true

  # Owner of an endpoint can edit it
  def authorize(:update_endpoint, %{id: user_id}, %{user_id: user_id}), do: true

  # Deny everything else
  def authorize(_, _, _), do: false
end

# In a controller or LiveView
with :ok <- Bodyguard.permit(BlackBoex.Endpoints, :update_endpoint, current_user, endpoint) do
  BlackBoex.Endpoints.update_endpoint(endpoint, params)
end
```

**Query Scoping:**

```elixir
defmodule BlackBoex.Endpoints.Endpoint do
  @behaviour Bodyguard.Schema

  import Ecto.Query

  def scope(query, %{role: :superadmin}, _), do: query
  def scope(query, %{organization_id: org_id}, _) do
    from e in query, where: e.organization_id == ^org_id
  end
end

# Usage
Endpoint
|> Bodyguard.scope(current_user)
|> Repo.all()
```

### 5.2 LetMe

- **Repo**: https://github.com/woylie/let_me
- **Hex**: `{:let_me, "~> 1.2"}`
- **Philosophy**: Authorization DSL with introspection

**DSL Example:**

```elixir
defmodule BlackBoex.Policy do
  use LetMe.Policy

  object :endpoint do
    action :create do
      allow role: :admin
      allow role: :member
      desc "Create a new API endpoint"
    end

    action :read do
      allow :same_organization
      desc "View endpoint details"
    end

    action :update do
      allow role: :admin
      allow [:own_resource, role: :member]
      desc "Update endpoint configuration"
    end

    action :delete do
      allow role: :admin
      desc "Delete an endpoint"
    end

    action :deploy do
      allow role: :admin
      allow role: :member
      deny :over_quota
      desc "Deploy endpoint to production"
    end
  end
end
```

**Check Module:**

```elixir
defmodule BlackBoex.Policy.Checks do
  def role(%{current_user: %{role: role}}, _object, role), do: true
  def role(_, _, _), do: false

  def same_organization(%{current_user: %{organization_id: org_id}}, %{organization_id: org_id}), do: true
  def same_organization(_, _), do: false

  def own_resource(%{current_user: %{id: id}}, %{user_id: id}), do: true
  def own_resource(_, _), do: false

  def over_quota(%{current_user: user}, _object) do
    BlackBoex.Billing.over_quota?(user.organization_id)
  end
end
```

**Introspection (useful for admin UI):**

```elixir
BlackBoex.Policy.list_rules()
# => [%LetMe.Rule{action: :endpoint_create, allow: [...], ...}, ...]

BlackBoex.Policy.list_rules(allow: {:role, :member})
# => rules where members have access

BlackBoex.Policy.get_rule(:endpoint_deploy)
# => %LetMe.Rule{deny: [:over_quota], ...}
```

### 5.3 Comparison

| Feature               | Bodyguard            | LetMe                |
|-----------------------|----------------------|----------------------|
| Approach              | Pattern matching     | DSL + checks module  |
| Introspection         | No                   | Yes (list/get rules) |
| Query scoping         | Built-in behaviour   | Schema behaviour     |
| Field redaction       | No                   | Yes                  |
| Typespec generation   | No                   | Yes (Dialyzer-ready) |
| Deny rules            | Manual               | Built-in `deny`      |
| Dependencies          | Zero                 | Zero                 |
| Learning curve        | Very low             | Low                  |
| Flexibility           | Maximum              | Structured           |

**Recommendation for BlackBoex: LetMe** — the DSL approach maps well to BlackBoex's needs (multiple objects, role hierarchy, deny rules for quota enforcement), and introspection is valuable for rendering permission docs in the admin panel. The auto-generated typespecs catch invalid action atoms at compile time via Dialyzer.

---

## 6. Audit Logging

### 6.1 ExAudit (Recommended)

- **Repo**: https://github.com/ZennerIoT/ex_audit
- **Hex**: `{:ex_audit, "~> 0.10"}`
- **Approach**: Transparent Ecto.Repo wrapper

ExAudit wraps your Repo and automatically tracks insert/update/delete operations without changing existing code.

**Setup:**

```elixir
# lib/blackboex/repo.ex
defmodule BlackBoex.Repo do
  use Ecto.Repo,
    otp_app: :blackboex,
    adapter: Ecto.Adapters.Postgres

  use ExAudit.Repo
end

# config/config.exs
config :ex_audit,
  ecto_repos: [BlackBoex.Repo],
  version_schema: BlackBoex.Audit.Version,
  tracked_schemas: [
    BlackBoex.Accounts.User,
    BlackBoex.Endpoints.Endpoint,
    BlackBoex.Settings.LlmApiKey
  ]
```

**Version Schema:**

```elixir
defmodule BlackBoex.Audit.Version do
  use Ecto.Schema
  import Ecto.Changeset

  schema "versions" do
    field :patch, ExAudit.Type.Patch
    field :entity_id, :binary_id
    field :entity_schema, ExAudit.Type.Schema
    field :action, ExAudit.Type.Action
    field :recorded_at, :utc_datetime
    field :rollback, :boolean, default: false

    # Custom fields
    belongs_to :actor, BlackBoex.Accounts.User
    field :ip_address, :string
    field :user_agent, :string
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:patch, :entity_id, :entity_schema, :action, :recorded_at, :rollback])
    |> cast(params, [:actor_id, :ip_address, :user_agent])
  end
end
```

**Tracking Actor Context via Plug:**

```elixir
defmodule BlackBoexWeb.Plugs.AuditContext do
  def init(opts), do: opts

  def call(conn, _opts) do
    if user = conn.assigns[:current_user] do
      ExAudit.track(
        actor_id: user.id,
        ip_address: to_string(:inet_parse.ntoa(conn.remote_ip)),
        user_agent: Plug.Conn.get_req_header(conn, "user-agent") |> List.first()
      )
    end

    conn
  end
end
```

**Querying History:**

```elixir
# Get all versions of an endpoint
BlackBoex.Repo.history(endpoint)

# Revert to previous version
BlackBoex.Repo.revert(version)
```

### 6.2 PaperTrail

- **Repo**: https://github.com/izelnakri/paper_trail
- **Hex**: `{:paper_trail, "~> 0.14"}`
- **Approach**: Explicit function calls (PaperTrail.insert/update/delete)

PaperTrail requires replacing `Repo.insert` with `PaperTrail.insert`, etc. It stores full item_changes as a map and supports origin tracking, metadata, and originator.

**Usage:**

```elixir
changeset = Endpoint.changeset(%Endpoint{}, params)

PaperTrail.insert(changeset,
  originator: current_user,
  origin: "web:admin",
  meta: %{ip_address: remote_ip}
)
# => {:ok, %{model: %Endpoint{}, version: %PaperTrail.Version{}}}
```

**Version Fields:**
- `event` — "insert", "update", or "delete"
- `item_type` — schema name
- `item_id` — record ID
- `item_changes` — map of all changes
- `originator_id` — who made the change
- `origin` — source reference
- `meta` — custom metadata

### 6.3 Custom Audit Log (Alternative)

For operation-level auditing (not row-level), a custom approach is often better:

```elixir
defmodule BlackBoex.Audit do
  alias BlackBoex.Audit.AuditLog

  @spec log(atom(), map(), map()) :: {:ok, AuditLog.t()} | {:error, term()}
  def log(action, actor, params \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      action: action,
      actor_id: actor.id,
      actor_email: actor.email,
      resource_type: params[:resource_type],
      resource_id: params[:resource_id],
      changes: params[:changes],
      metadata: params[:metadata],
      ip_address: params[:ip_address]
    })
    |> Repo.insert()
  end
end

# Usage in contexts
def deploy_endpoint(scope, endpoint) do
  with :ok <- Policy.authorize(:endpoint_deploy, scope, endpoint),
       {:ok, deployed} <- do_deploy(endpoint) do
    Audit.log(:endpoint_deployed, scope.current_user, %{
      resource_type: "endpoint",
      resource_id: endpoint.id,
      metadata: %{version: deployed.version}
    })

    {:ok, deployed}
  end
end
```

### 6.4 Comparison

| Feature           | ExAudit              | PaperTrail           | Custom               |
|-------------------|----------------------|----------------------|----------------------|
| Integration       | Transparent (Repo)   | Explicit calls       | Explicit calls       |
| Tracking level    | Row changes          | Row changes          | Operations           |
| Diff format       | Binary patch         | Map of changes       | Custom               |
| Rollback          | Yes                  | No (manual)          | No                   |
| Custom fields     | Yes                  | Yes (meta)           | Full control         |
| Code changes      | Minimal              | Replace Repo calls   | New code needed      |
| Multi-table ops   | Per-table            | Per-call             | Per-operation        |

**Recommendation: ExAudit for row-level + Custom for operation-level.** Use ExAudit to transparently track data changes on critical schemas, and a custom audit log for high-level business operations (deploy, billing events, permission changes).

---

## 7. Settings UI with LiveView

### 7.1 Architecture Patterns

**Tabbed Settings Page with push_patch:**

```elixir
defmodule BlackBoexWeb.SettingsLive do
  use BlackBoexWeb, :live_view

  @tabs ~w(general api-keys billing team security)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "general")
    tab = if tab in @tabs, do: tab, else: "general"

    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex gap-8">
      <nav class="w-48 flex-shrink-0">
        <.settings_nav active_tab={@active_tab} />
      </nav>

      <div class="flex-1">
        <.live_component
          module={tab_component(@active_tab)}
          id={"settings-#{@active_tab}"}
          current_user={@current_user}
          organization={@current_organization}
        />
      </div>
    </div>
    """
  end

  defp tab_component("general"), do: BlackBoexWeb.Settings.GeneralComponent
  defp tab_component("api-keys"), do: BlackBoexWeb.Settings.ApiKeysComponent
  defp tab_component("billing"), do: BlackBoexWeb.Settings.BillingComponent
  defp tab_component("team"), do: BlackBoexWeb.Settings.TeamComponent
  defp tab_component("security"), do: BlackBoexWeb.Settings.SecurityComponent

  defp settings_nav(assigns) do
    ~H"""
    <ul class="space-y-1">
      <li :for={tab <- @tabs}>
        <.link
          patch={~p"/settings/#{tab}"}
          class={[
            "block px-3 py-2 rounded-md text-sm",
            if(@active_tab == tab, do: "bg-primary text-primary-foreground", else: "hover:bg-muted")
          ]}
        >
          {tab_label(tab)}
        </.link>
      </li>
    </ul>
    """
  end
end
```

**LiveComponent for Isolated State (API Keys Tab):**

```elixir
defmodule BlackBoexWeb.Settings.ApiKeysComponent do
  use BlackBoexWeb, :live_component

  alias BlackBoex.Settings

  @impl true
  def update(assigns, socket) do
    api_keys = Settings.list_api_keys(assigns.organization)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:api_keys, api_keys)
     |> assign(:show_form, false)}
  end

  @impl true
  def handle_event("add-key", _params, socket) do
    changeset = Settings.change_api_key(%Settings.LlmApiKey{})
    {:noreply, assign(socket, show_form: true, changeset: changeset)}
  end

  @impl true
  def handle_event("save-key", %{"llm_api_key" => params}, socket) do
    case Settings.create_api_key(socket.assigns.organization, params) do
      {:ok, _key} ->
        api_keys = Settings.list_api_keys(socket.assigns.organization)
        {:noreply, assign(socket, api_keys: api_keys, show_form: false)}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete-key", %{"id" => id}, socket) do
    Settings.delete_api_key(socket.assigns.organization, id)
    api_keys = Settings.list_api_keys(socket.assigns.organization)
    {:noreply, assign(socket, api_keys: api_keys)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-lg font-semibold">LLM API Keys</h2>
        <.button phx-click="add-key" phx-target={@myself}>
          Add API Key
        </.button>
      </div>

      <div :if={@show_form} class="mb-6 p-4 border rounded-lg">
        <.form for={@changeset} phx-submit="save-key" phx-target={@myself}>
          <.input field={@changeset[:provider]} type="select"
            label="Provider"
            options={[{"OpenAI", :openai}, {"Anthropic", :anthropic}, {"Google", :google}]} />
          <.input field={@changeset[:label]} type="text" label="Label" />
          <.input field={@changeset[:api_key]} type="password" label="API Key" />
          <.button type="submit">Save</.button>
        </.form>
      </div>

      <div class="space-y-3">
        <div :for={key <- @api_keys} class="flex items-center justify-between p-3 border rounded">
          <div>
            <span class="font-medium">{key.label}</span>
            <span class="text-sm text-muted-foreground ml-2">{key.provider}</span>
            <span class="text-xs text-muted-foreground ml-2">
              ****{String.slice(key.api_key_hint, -4..-1)}
            </span>
          </div>
          <.button
            variant="destructive"
            size="sm"
            phx-click="delete-key"
            phx-value-id={key.id}
            phx-target={@myself}
            data-confirm="Are you sure?"
          >
            Remove
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
```

### 7.2 Form Patterns

**Real-time Validation with phx-change:**

```elixir
# LiveView forms auto-recover on reconnect when they have:
# 1. A phx-change binding
# 2. An id attribute

<.form for={@form} phx-change="validate" phx-submit="save" id="settings-form">
  <.input field={@form[:name]} label="Organization Name" />
  <.input field={@form[:slug]} label="URL Slug" />
  <.button type="submit" phx-disable-with="Saving...">Save</.button>
</.form>
```

**Handling in LiveView:**

```elixir
def handle_event("validate", %{"organization" => params}, socket) do
  changeset =
    socket.assigns.organization
    |> Organization.changeset(params)
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, form: to_form(changeset))}
end

def handle_event("save", %{"organization" => params}, socket) do
  case Accounts.update_organization(socket.assigns.organization, params) do
    {:ok, org} ->
      {:noreply,
       socket
       |> put_flash(:info, "Settings updated.")
       |> assign(:organization, org)}

    {:error, changeset} ->
      {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

### 7.3 SaladUI Integration

BlackBoex uses SaladUI (shadcn/ui port for Phoenix). Key components for settings pages:

- `SaladUI.Card` — section containers
- `SaladUI.Tabs` — tab navigation
- `SaladUI.Form` — form elements with validation states
- `SaladUI.Dialog` — confirmation modals
- `SaladUI.Alert` — flash messages and warnings
- `SaladUI.Badge` — status indicators
- `SaladUI.Table` — data tables for API keys, team members

---

## 8. Architecture Recommendation for BlackBoex

### 8.1 Selected Stack

| Concern               | Library / Approach                          |
|-----------------------|---------------------------------------------|
| Admin panel           | **Backpex** (LiveResource-based CRUD)       |
| Feature flags         | **FunWithFlags** (Ecto persistence)         |
| Authentication        | **phx.gen.auth** (magic links) + Ueberauth  |
| Authorization (RBAC)  | **LetMe** (DSL + introspection)             |
| Multi-tenancy         | **Foreign key** (org_id on all tables)       |
| Billing               | **Stripity Stripe** + internal usage events  |
| API key encryption    | **Cloak/Cloak.Ecto** (AES-GCM)             |
| Audit logging (rows)  | **ExAudit** (transparent Repo tracking)      |
| Audit logging (ops)   | **Custom** AuditLog context                  |
| Background jobs       | **Oban** (usage aggregation, billing sync)   |
| Config cache          | **ETS** (GenServer-managed with TTL)         |
| Settings UI           | **LiveView** + LiveComponent + SaladUI       |
| Rate limiting         | **ETS** (sliding window per org/user)        |

### 8.2 Module Layout

```text
apps/blackboex/lib/blackboex/
  accounts/
    user.ex                  # Schema (from phx.gen.auth)
    user_token.ex            # Schema (from phx.gen.auth)
    organization.ex          # Schema
    membership.ex            # Schema (user <-> org, with role)
    scope.ex                 # Authorization scope struct
  accounts.ex                # Context

  settings/
    llm_api_key.ex           # Schema (encrypted with Cloak)
    rate_limit_config.ex     # Schema (per-org rate limits)
    config_cache.ex          # GenServer + ETS cache
  settings.ex                # Context

  billing/
    usage_event.ex           # Schema (per-request tracking)
    daily_usage.ex           # Schema (aggregated summaries)
    subscription.ex          # Schema (Stripe subscription mirror)
    workers/
      usage_aggregator.ex    # Oban worker
      stripe_sync.ex         # Oban worker
  billing.ex                 # Context

  endpoints/
    endpoint.ex              # Schema
    endpoint_version.ex      # Schema (code versions)
  endpoints.ex               # Context

  audit/
    version.ex               # ExAudit version schema
    audit_log.ex             # Custom operation-level audit
  audit.ex                   # Context

  policy.ex                  # LetMe policy (authorization DSL)
  policy/checks.ex           # LetMe check functions

  vault.ex                   # Cloak vault
  encrypted/binary.ex        # Cloak.Ecto encrypted type

apps/blackboex_web/lib/blackboex_web/
  live/
    settings_live.ex          # Tabbed settings page
    settings/
      general_component.ex    # Org name, slug, etc.
      api_keys_component.ex   # LLM API key management
      billing_component.ex    # Usage dashboard, plan management
      team_component.ex       # Invite members, manage roles
      security_component.ex   # Sessions, 2FA, audit log viewer

  controllers/
    webhook_controller.ex     # Stripe webhooks

  plugs/
    audit_context.ex          # ExAudit actor tracking
    set_organization.ex       # Multi-tenancy org scope
    rate_limit.ex             # API rate limiting

  # Admin panel (Backpex)
  live/admin/
    user_live.ex              # Backpex LiveResource
    organization_live.ex      # Backpex LiveResource
    endpoint_live.ex          # Backpex LiveResource
    audit_log_live.ex         # Backpex LiveResource
```

### 8.3 Router Structure

```elixir
# router.ex

# Public routes
scope "/", BlackBoexWeb do
  pipe_through [:browser]

  # phx.gen.auth routes
  get "/users/log-in", UserSessionController, :new
  post "/users/log-in", UserSessionController, :create
  # ...
end

# Authenticated user routes
scope "/", BlackBoexWeb do
  pipe_through [:browser, :require_authenticated_user, :set_organization]

  live_session :authenticated,
    on_mount: [{BlackBoexWeb.UserAuth, :ensure_authenticated}] do
    live "/dashboard", DashboardLive
    live "/endpoints", EndpointLive.Index
    live "/endpoints/:id", EndpointLive.Show
    live "/settings", SettingsLive
    live "/settings/:tab", SettingsLive
  end
end

# Admin panel (Backpex)
scope "/admin", BlackBoexWeb.Admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  # Backpex resources
  live_session :admin,
    on_mount: [{BlackBoexWeb.UserAuth, :ensure_admin}] do
    # Backpex live resources are mounted here
    live "/users", UserLive, :index
    live "/users/new", UserLive, :new
    live "/users/:id", UserLive, :show
    live "/users/:id/edit", UserLive, :edit
    # ... same pattern for other admin resources
  end

  # Feature flags dashboard
  forward "/feature-flags", FunWithFlags.UI.Router, namespace: "admin"
end

# API routes (for published endpoints)
scope "/api/v1", BlackBoexWeb.API do
  pipe_through [:api, :api_auth, :rate_limit, :track_usage]

  # Dynamic endpoint routing
  get "/:org_slug/:endpoint_slug", EndpointController, :call
  post "/:org_slug/:endpoint_slug", EndpointController, :call
end

# Stripe webhooks
scope "/webhooks", BlackBoexWeb do
  pipe_through [:api]
  post "/stripe", WebhookController, :stripe
end
```

### 8.4 Implementation Priority

**Phase 1 — Foundation (Sprint 1-2):**
1. `phx.gen.auth` with magic links
2. Organization + Membership schemas with foreign-key multi-tenancy
3. LetMe policy module with basic roles (owner, admin, member)
4. Cloak vault + encrypted API key storage
5. Settings LiveView (general + API keys tabs)

**Phase 2 — Admin & Observability (Sprint 3-4):**
1. Backpex admin panel for Users, Organizations, Endpoints
2. ExAudit for row-level change tracking
3. Custom AuditLog for operation-level events
4. FunWithFlags for feature flags
5. Settings: team management tab

**Phase 3 — Billing & Limits (Sprint 5-6):**
1. Stripe integration (Stripity Stripe)
2. Usage event tracking
3. Oban workers for aggregation and Stripe sync
4. Rate limiting (ETS-based)
5. Settings: billing tab with usage dashboard
6. Stripe webhook handler

**Phase 4 — Polish (Sprint 7+):**
1. Ueberauth OAuth (GitHub, Google)
2. Advanced feature flag gates (percentage rollouts)
3. Admin metrics and dashboards
4. Security tab (active sessions, audit log viewer)
5. Export/reporting capabilities

---

## Sources

### Admin Panel
- [Backpex GitHub](https://github.com/naymspace/backpex)
- [Backpex Documentation](https://hexdocs.pm/backpex/what-is-backpex.html)
- [Backpex LiveResource API](https://hexdocs.pm/backpex/Backpex.LiveResource.html)
- [Kaffy GitHub](https://github.com/aesmail/kaffy)
- [Ash Admin GitHub](https://github.com/ash-project/ash_admin)
- [Backpex ElixirCasts](https://elixircasts.io/backpex-phoenix-admin-panel)
- [Building Admin Dashboards with Backpex](https://james-carr.org/posts/2024-08-27-phoenix-admin-with-backpex/)

### Configuration & Feature Flags
- [FunWithFlags GitHub](https://github.com/tompave/fun_with_flags)
- [FunWithFlags HexDocs](https://hexdocs.pm/fun_with_flags/FunWithFlags.html)
- [FunWithFlags in Phoenix (DockYard)](https://dockyard.com/blog/2023/02/28/how-to-add-feature-flags-in-a-phoenix-application-using-fun_with_flags)
- [Cloak GitHub](https://github.com/danielberkompas/cloak)
- [Cloak.Ecto HexDocs](https://hexdocs.pm/cloak_ecto/readme.html)

### Authentication
- [Phoenix Magic Link Auth Tour](https://mikezornek.com/posts/2025/5/phoenix-magic-link-authentication/)
- [Ueberauth GitHub](https://github.com/ueberauth/ueberauth)
- [phx_gen_auth GitHub](https://github.com/aaronrenner/phx_gen_auth)

### Multi-Tenancy
- [Multitenancy in Elixir (Curiosum)](https://www.curiosum.com/blog/multitenancy-in-elixir)
- [Triplex GitHub](https://github.com/ateliware/triplex)
- [Ecto Multi-tenancy Guide](https://github.com/elixir-ecto/ecto/blob/master/guides/howtos/Multi%20tenancy%20with%20query%20prefixes.md)
- [Multi-tenancy with Postgres and Ecto (Viget)](https://www.viget.com/articles/multi-tenancy-with-postgres-schemas-and-ecto)

### Billing
- [Stripity Stripe HexDocs](https://hexdocs.pm/stripity_stripe/api-reference.html)
- [Stripe Usage-Based Billing](https://docs.stripe.com/billing/subscriptions/usage-based/implementation-guide)
- [Stripe Billing Meters](https://docs.stripe.com/api/billing/meter)

### Authorization
- [Bodyguard GitHub](https://github.com/schrockwell/bodyguard)
- [LetMe GitHub](https://github.com/woylie/let_me)
- [LetMe HexDocs](https://hexdocs.pm/let_me/readme.html)
- [Authorization in Phoenix (AppSignal)](https://blog.appsignal.com/2021/11/02/authorization-and-policy-scopes-for-phoenix-apps.html)
- [Authorization in Elixir (Curiosum)](https://www.curiosum.com/blog/authorization-access-control-elixirconf)

### Audit Logging
- [ExAudit GitHub](https://github.com/ZennerIoT/ex_audit)
- [PaperTrail GitHub](https://github.com/izelnakri/paper_trail)
- [Audit Logs Forum Discussion](https://elixirforum.com/t/audit-logs-ecto-database/45635)
- [Tracking Changes in Phoenix (Luiz Damim)](https://luizdamim.com/blog/tracking-changes-with-context-using-phoenix-and-ecto/)

### LiveView Patterns
- [Phoenix LiveView Form Bindings](https://hexdocs.pm/phoenix_live_view/form-bindings.html)
- [LiveComponent SRP Pattern (Elixir School)](https://elixirschool.com/blog/live-view-live-component)
- [LiveView Patching Navigation](https://dev.to/hexshift/mastering-phoenix-liveview-patching-stateful-navigation-without-reloading-your-ui-k5p)
