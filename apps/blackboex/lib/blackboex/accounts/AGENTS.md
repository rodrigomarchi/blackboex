# Accounts Context — AGENTS.md

## Overview

The Accounts context (`Blackboex.Accounts`) owns user identity, authentication,
session lifecycle, and the `Scope` struct that threads multi-tenant context
through every operation in the system.

**Key responsibilities:**

- User registration and email confirmation via magic link
- Session token issuance, reissue, and revocation
- Password management (optional — magic link is the primary auth path)
- Email change with token verification
- Sudo mode (recent-authentication gate for sensitive settings)
- The `Scope` struct that carries `{user, organization, membership}` into every
  domain call

**Modules in this directory:**

| File | Purpose |
|------|---------|
| `scope.ex` | The Scope struct — central carrier for caller context |
| `user.ex` | User schema and changesets |
| `user_token.ex` | Token schema, generation, and verification |
| `user_notifier.ex` | Swoosh email delivery |
| `../accounts.ex` | Public facade — the only entry point for callers |

---

## Scope Struct

`Blackboex.Accounts.Scope` is the single most important struct in the system.
Every domain context function that touches tenant-specific data receives a Scope
and uses it to enforce ownership boundaries.

All operations must use Scope for IDOR protection.

### Fields

```elixir
defstruct user: nil, organization: nil, membership: nil
```

| Field | Type | Description |
|-------|------|-------------|
| `user` | `%User{}` or `nil` | The authenticated user making the request |
| `organization` | `%Organization{}` or `nil` | The active organization for this request |
| `membership` | `%Membership{}` or `nil` | The user's membership record in that org (carries role) |

### Construction

```elixir
# Step 1 — user only (right after session lookup)
scope = Scope.for_user(user)       # returns %Scope{user: user}
scope = Scope.for_user(nil)        # returns nil (unauthenticated)

# Step 2 — add org context (after SetOrganization plug/hook)
scope = Scope.with_organization(scope, org, membership)
# returns %Scope{user: user, organization: org, membership: membership}
```

### How Scope Flows Through the System

The flow is linear and deterministic on every request/mount:

```
HTTP request / LiveView mount
        |
        v
UserAuth.fetch_current_scope_for_user/2  (Plug, every request)
  - reads :user_token from session
  - calls Accounts.get_user_by_session_token/1
  - assigns conn.assigns.current_scope = Scope.for_user(user)
        |
        v
Plugs.SetOrganization.call/2  (Plug, controller routes)
OR
Hooks.SetOrganization.on_mount/4  (LiveView on_mount)
  - reads :organization_id from session
  - calls Organizations.get_organization/1
  - calls Organizations.get_user_membership/2
  - reassigns current_scope = Scope.with_organization(scope, org, membership)
  - falls back to user's first org if session org_id is missing or stale
        |
        v
socket.assigns.current_scope  (LiveView)
conn.assigns.current_scope    (Controllers)
  - always available in templates and event handlers
  - contains the fully-populated scope (or nil org if user has no orgs)
        |
        v
Domain context calls
  e.g. Apis.list_apis(scope)
       Billing.get_subscription(scope)
  - use scope.organization.id for all tenant-scoped queries
  - use scope.user.id for user-scoped ownership checks
```

Multi-tenancy details: see `organizations/AGENTS.md`.

Auth flow details: see `controllers/AGENTS.md`.

---

## User Schema (`Blackboex.Accounts.User`)

### Database Fields

| Field | Type | Notes |
|-------|------|-------|
| `id` | `integer` | Primary key |
| `email` | `string` | Unique, max 160 chars, validated format |
| `hashed_password` | `string` | Bcrypt hash, redacted in logs |
| `confirmed_at` | `utc_datetime_usec` | Nil until first magic-link login |
| `is_platform_admin` | `boolean` | Default false; platform-wide admin flag |
| `inserted_at` | `utc_datetime_usec` | Auto-set by Ecto |
| `updated_at` | `utc_datetime_usec` | Auto-set by Ecto |

### Virtual Fields

| Field | Type | Notes |
|-------|------|-------|
| `password` | `string` | Redacted; holds plaintext during changeset validation only |
| `authenticated_at` | `utc_datetime_usec` | Populated from token at session load time; not persisted |

### Changesets

| Changeset | Fields | Key Validations | Options |
|-----------|--------|-----------------|---------|
| `email_changeset/3` | `:email` | Format (`~r/^[^@,;\s]+@[^@,;\s]+$/`), max 160 chars, uniqueness (unsafe + DB constraint), rejects no-op updates | `validate_unique: false` — skip uniqueness for live form validation |
| `password_changeset/3` | `:password`, `:password_confirmation` | Min 12 / max 72 chars, max 72 bytes (Bcrypt limit), confirmation match | `hash_password: false` — skip hashing for live form validation |
| `admin_changeset/3` | `:email`, `:is_platform_admin`, `:confirmed_at` | No `validate_email` — avoids false uniqueness errors on unchanged emails | Backpex admin only |
| `confirm_changeset/1` | — | Sets `confirmed_at` to current UTC | — |

### Password Verification

`User.valid_password?/2` uses `Bcrypt.verify_pass/2`. If the user has no
`hashed_password` (magic-link-only accounts), calls `Bcrypt.no_user_verify/0`
to consume constant time and prevent timing attacks, then returns `false`.

---

## UserToken Schema (`Blackboex.Accounts.UserToken`)

### Database Fields

| Field | Type | Notes |
|-------|------|-------|
| `token` | `binary` | Raw bytes for session; SHA-256 hash for email tokens |
| `context` | `string` | Token type identifier (see below) |
| `sent_to` | `string` | Email address the token was sent to (email tokens only) |
| `authenticated_at` | `utc_datetime_usec` | When the auth action occurred (session tokens) |
| `user_id` | `integer` | FK to users |
| `inserted_at` | `utc_datetime_usec` | Creation time; used for expiry calculations |

Note: `updated_at` is disabled (`timestamps updated_at: false`).

### Token Contexts

| Context value | Purpose | Storage | Expiry |
|---------------|---------|---------|--------|
| `"session"` | Browser session | Raw bytes in DB | 14 days |
| `"login"` | Magic link login email | SHA-256 hash in DB | 15 minutes |
| `"change:#{old_email}"` | Email change confirmation | SHA-256 hash in DB | 7 days |

### Token Generation

- **`build_session_token/1`** — 32 random bytes, stored raw (not hashed); returns `{raw_token, %UserToken{}}`.
- **`build_email_token/2`** — 32 random bytes, SHA-256 hashed; returns `{Base.url_encode64(raw), %UserToken{token: hash}}`. Only the hash is stored. `sent_to` is set to current email so stale tokens auto-invalidate on email change.

### Token Verification

All verify functions return `{:ok, Ecto.Query.t()}` or `:error` — query is not executed inside UserToken; caller runs it via `Repo.one/1`.

- **`verify_session_token_query/1`** — raw binary match, context `"session"`, last 14 days; selects `{user_with_authenticated_at, token_inserted_at}`
- **`verify_magic_link_token_query/1`** — URL-decode + hash, context `"login"`, last 15 min, `sent_to == user.email`; `:error` on invalid base64
- **`verify_change_email_token_query/2`** — same decode+hash, context starts with `"change:"`, last 7 days

### Token Deletion

- Password change and magic-link confirmation for unconfirmed users delete ALL
  user tokens (via `update_user_and_delete_all_tokens/1`)
- Session logout deletes only the specific session token by raw value
- Email change deletes tokens for context `"change:#{email}"`
- Expired tokens accumulate until next rotation event; there is no background
  pruning job

---

## UserNotifier (`Blackboex.Accounts.UserNotifier`)

Thin Swoosh wrapper. Plain text emails. Sender: `{"Blackboex", "contact@example.com"}` — update for production. Two functions: `deliver_login_instructions/2` (dispatches on `confirmed_at`: confirmation vs. magic link email) and `deliver_update_email_instructions/2` (email change URL). Both return `{:ok, %Swoosh.Email{}}`.

---

## Public API (Accounts Facade)

All public functions live in `Blackboex.Accounts`. Domain code must not call
`User`, `UserToken`, or `UserNotifier` directly.

### Database Getters

```elixir
@spec get_user(id :: integer()) :: User.t() | nil
get_user(id)
# Safe for external IDs. Returns nil, never raises.

@spec get_user!(id :: integer()) :: User.t()
get_user!(id)
# Only when absence is a programming error, not user input.

@spec get_user_by_email(email :: String.t()) :: User.t() | nil
get_user_by_email(email)
# Case-sensitive lookup.

@spec get_user_by_email_and_password(email :: String.t(), password :: String.t()) :: User.t() | nil
get_user_by_email_and_password(email, password)
# Returns user on valid credentials, nil otherwise.
# Always runs Bcrypt (even if user not found) to prevent timing attacks.
```

### Registration

```elixir
@spec register_user(attrs :: map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, :registration_failed}
register_user(attrs)
```

Runs an `Ecto.Multi` transaction:
1. Inserts the `User` via `email_changeset`
2. Creates a personal `Organization` (name: `"#{email_prefix}-#{random_suffix}"`)
3. Creates a `Membership` (role: `:owner`) linking user to that org

Returns `{:ok, user}` on success. Returns `{:error, changeset}` if user
insertion fails. Returns `{:error, :registration_failed}` if org/membership
steps fail (should not happen under normal conditions).

### Settings

```elixir
@spec sudo_mode?(user :: User.t(), minutes :: integer()) :: boolean()
sudo_mode?(user, minutes \\ -20)
# True if user.authenticated_at is within the last 20 minutes.
# authenticated_at is a virtual field set at session load time.

@spec change_user_email(user :: User.t(), attrs :: map(), opts :: keyword()) :: Ecto.Changeset.t()
change_user_email(user, attrs \\ %{}, opts \\ [])

@spec update_user_email(user :: User.t(), token :: String.t()) ::
        {:ok, User.t()} | {:error, :transaction_aborted}
update_user_email(user, token)
# Verifies the change token, updates email, deletes "change:#{email}" tokens.

@spec change_user_password(user :: User.t(), attrs :: map(), opts :: keyword()) :: Ecto.Changeset.t()
change_user_password(user, attrs \\ %{}, opts \\ [])

@spec update_user_password(user :: User.t(), attrs :: map()) ::
        {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
update_user_password(user, attrs)
# On success: updates user, deletes ALL session tokens, returns expired token list.
# Caller should call UserAuth.disconnect_sessions/1 with the expired tokens.
```

### Session Management

```elixir
@spec generate_user_session_token(user :: User.t()) :: binary()
generate_user_session_token(user)
# Inserts a new UserToken (context: "session"), returns the raw token binary.

@spec get_user_by_session_token(token :: binary()) :: {User.t(), DateTime.t()} | nil
get_user_by_session_token(token)
# Returns {user_with_authenticated_at, token_inserted_at} or nil if expired/invalid.

@spec delete_user_session_token(token :: binary()) :: :ok
delete_user_session_token(token)
# Deletes one specific session token. Used on logout.
```

### Magic Link

```elixir
@spec get_user_by_magic_link_token(token :: String.t()) :: User.t() | nil
get_user_by_magic_link_token(token)
# Verifies the token (15-min window). Returns user or nil.

@spec login_user_by_magic_link(token :: String.t()) ::
        {:ok, {User.t(), [UserToken.t()]}} | {:error, :not_found}
login_user_by_magic_link(token)
# Three cases:
#   1. Already confirmed — deletes the magic link token, returns {user, []}
#   2. Unconfirmed, no password — confirms account, deletes ALL tokens
#   3. Unconfirmed, has password — raises (security violation, cannot happen
#      in default implementation)
```

### Email Delivery

```elixir
@spec deliver_login_instructions(user :: User.t(), magic_link_url_fun :: (String.t() -> String.t())) ::
        {:ok, Swoosh.Email.t()} | {:error, term()}
deliver_login_instructions(user, magic_link_url_fun)
# Builds email token (context: "login"), inserts it, sends email.
# magic_link_url_fun receives the encoded token and returns a full URL.

@spec deliver_user_update_email_instructions(
        user :: User.t(),
        current_email :: String.t(),
        update_email_url_fun :: (String.t() -> String.t())
      ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
deliver_user_update_email_instructions(user, current_email, update_email_url_fun)
# Builds email token (context: "change:#{current_email}"), inserts, sends.
```

---

## Testing

Fixtures live in `test/support/fixtures/accounts_fixtures.ex` (`Blackboex.AccountsFixtures`).

- `unique_user_email/0`, `valid_user_password/0` — generators
- `user_fixture/1`, `unconfirmed_user_fixture/1` — create confirmed/unconfirmed users
- `user_scope_fixture/0,1` — create or wrap a user in `Scope.for_user/1`
- `extract_user_token/1` — pulls raw token from email body (sentinel-based)
- `generate_user_magic_link_token/1` — returns `{encoded_token, hashed_token}` for direct verification tests
- `offset_user_token/3` — backdates/forward-dates `inserted_at` and `authenticated_at` for expiry tests
- `override_token_authenticated_at/2` — sets `authenticated_at` on a specific token for `sudo_mode?` tests

ConnCase helpers (`test/support/conn_case.ex`):
- `setup :register_and_log_in_user` — injects `%{conn:, user:, scope:}` into test context
- `log_in_user/2,3` — manual login; does NOT run SetOrganization (set up `scope.organization` separately if needed)

Users are created via real `Accounts.register_user/1` (not ExMachina) to ensure every test user has a valid scope with a personal org. For other entities, use `Blackboex.Factory`.

---

## Gotchas

### Token Comparison Must Use Plug.Crypto.secure_compare

Never compare session tokens with `==`. The raw token binary should be treated
as a secret. `UserToken.verify_session_token_query/1` uses a DB lookup (which
is effectively constant-time at the application level), but any manual token
comparison in callers must use `Plug.Crypto.secure_compare/2`.

### Bcrypt and Password Length

Bcrypt silently truncates passwords at 72 bytes. The `password_changeset`
validates `max: 72, count: :bytes` to prevent users from setting passwords
that appear to work but are silently truncated, which would allow an attacker
with a shorter password to authenticate.

### Email Uniqueness — `unsafe_validate_unique`

`email_changeset` calls `unsafe_validate_unique(:email, Repo)` before the DB
unique constraint. This gives a user-friendly error message without waiting for
a constraint violation. The "unsafe" name means it can have a TOCTOU race
condition in concurrent registrations — the real uniqueness guarantee is the DB
`unique_constraint`. Both checks are needed.

### Magic Link Security: `sent_to == user.email`

The magic link verification query includes `where: token.sent_to == user.email`.
This means if a user changes their email between requesting a magic link and
clicking it, the old link is invalidated. This is intentional and security-
critical — it prevents a scenario where an attacker who temporarily controls
an old email address can use a stale link.

### Session Fixation Prevention

`UserAuth.renew_session/2` calls `configure_session(renew: true)` + `clear_session()` on every login to rotate the session ID. A guard skips renewal when the same user is already logged in (prevents CSRF errors in open tabs).

### Magic Link Cannot Be Used for Unconfirmed Users with Passwords

`login_user_by_magic_link/1` raises if an unconfirmed user has `hashed_password` set. Cannot happen in the default implementation (no password registration path), but would be a security hole if both auth flows were added simultaneously.

### `Accounts.get_user!/1` is Not for External Input

`get_user!/1` raises `Ecto.NoResultsError` if the user does not exist. Use it
only when the ID comes from an already-trusted source (e.g., loaded from scope,
not from URL params). For user-facing ID lookups, always use `get_user/1` and
pattern-match the nil case.

### `authenticated_at` is a Virtual Field

`User.authenticated_at` is not stored in the `users` table. It is populated
from `UserToken.authenticated_at` during `verify_session_token_query` (the
query does `%{user | authenticated_at: token.authenticated_at}`). Its purpose
is to feed `sudo_mode?/2`. If you load a User directly from the DB without
going through the session token path, `authenticated_at` will be nil and
`sudo_mode?` will return false.

### Token Cleanup

There is no scheduled job to prune expired tokens. Expired tokens accumulate
in `users_tokens` until the user changes their password or magic-link-confirms
their account (which deletes all tokens). For high-traffic systems, consider
adding a periodic Oban job to clean up tokens older than their validity window.
