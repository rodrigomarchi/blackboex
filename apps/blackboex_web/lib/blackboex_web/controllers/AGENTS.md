# Controllers — AGENTS.md

This document covers every controller in `blackboex_web`: what it does, its routes, and gotchas.
Auth flow details live in `accounts/AGENTS.md`. Plug details live in `plugs/AGENTS.md`.

---

## Controllers Overview — When to Use Controllers vs LiveViews

| Use a **Controller** when | Use a **LiveView** when |
|---|---|
| Responding to a non-interactive HTTP request (redirect, static render, file download) | Any page with real-time updates or user interaction |
| Processing a form POST that triggers a one-shot action (login, logout, password update) | Forms that give instant feedback (validation, live search) |
| Handling webhooks or external callbacks (Stripe, OAuth) | Dashboards, editors, admin panels |
| Serving public read-only pages with no interactivity | Anything that benefits from PubSub / socket state |
| Returning JSON from a non-API-key-protected endpoint | — |

The golden rule: controllers own **request/response cycles**. LiveViews own **stateful sessions**.

---

## Controllers

### `BlackboexWeb.PageController`

**File:** `controllers/page_controller.ex`

| Action | Method | Path | Auth |
|--------|--------|------|------|
| `home/2` | GET | `/` | None (public) |

Checks `conn.assigns[:current_scope]`. If a logged-in user is present, redirects to `/dashboard`; otherwise renders the marketing home page (`page_html/home.html.heex`).

---

### `BlackboexWeb.UserSessionController`

**File:** `controllers/user_session_controller.ex`

| Action | Method | Path | Auth |
|--------|--------|------|------|
| `create/2` | POST | `/users/log-in` | None (public) |
| `create/2` (magic link) | POST | `/users/log-in` (with `user[token]`) | None (public) |
| `update_password/2` | POST | `/users/update-password` | `require_authenticated_user` |
| `delete/2` | DELETE | `/users/log-out` | None (session cleared regardless) |

**`create/2` — two login paths:**

1. **Magic link** — receives `user[token]` from the confirmation email. Calls `Accounts.login_user_by_magic_link/1`. On success, disconnects all other sessions for that token set, then calls `UserAuth.log_in_user/3`. On failure, flashes an error and redirects to `/users/log-in`.

2. **Email + password** — receives `user[email]` + `user[password]`. Calls `Accounts.get_user_by_email_and_password/2`. Error message deliberately does not distinguish "wrong password" from "unknown email" (prevents user enumeration). The email is echoed back (truncated to 160 chars) via flash.

**`update_password/2`:** Requires sudo mode (`Accounts.sudo_mode?/1` must be true). After update, existing tokens are invalidated and broadcast via `disconnect_sessions/1`, then a new session is created.

**`delete/2`:** Delegates entirely to `UserAuth.log_out_user/1`.

See `accounts/AGENTS.md § Auth Flow` for the complete step-by-step login sequence.

---

### `BlackboexWeb.WebhookController`

**File:** `controllers/webhook_controller.ex`

| Action | Method | Path | Auth |
|--------|--------|------|------|
| `handle/2` | POST | `/webhooks/stripe` | Stripe signature (HMAC-SHA256) |

No session or user auth. Routes through the `:api` pipeline only — no CSRF, no cookie parsing.

WebhookController verifies Stripe signature via `StripeClient.construct_webhook_event/3` with the raw body cached by `CacheBodyReader`. See `plugs/AGENTS.md` for `CacheBodyReader` details.

**Security order (must be preserved):**
1. `CacheBodyReader.get_raw_body/1` — retrieve raw bytes before JSON parsing discards them.
2. Extract `stripe-signature` header.
3. `StripeClient.client().construct_webhook_event/3` — HMAC verify. On `{:error, _}` → 400, never process.
4. `WebhookHandler.process_event/3` — idempotent business logic.
5. `{:error, :already_processed}` → 200 (Stripe retries on non-2xx; always acknowledge already-handled events).
6. `{:error, reason}` → 500 + log.

**CRITICAL:** Never mark an event processed before handling it. Correct order: check idempotency → process → mark processed.

---

### `BlackboexWeb.PublicApiController`

**File:** `controllers/public_api_controller.ex`

| Action | Method | Path | Auth |
|--------|--------|------|------|
| `show/2` | GET | `/p/:org_slug/:api_slug` | None (public) |

Serves public documentation for a published API. Uses a `with` chain:
1. Look up `Organization` by `org_slug`.
2. Look up `Api` by `api_slug` + `organization_id` with `status: "published"` and `visibility: "public"` enforced in the query pattern match.
3. On any miss → render `ErrorHTML` with status 404 (prevents leaking existence of unpublished/private APIs).

Renders `public_api_html/show.html.heex` with `api`, `org`, and `api_url`.

---

### `BlackboexWeb.ErrorHTML`

**File:** `controllers/error_html.ex`

Invoked by Phoenix for HTML error responses. Returns a plain-text status message derived from the template name via `Phoenix.Controller.status_message_from_template/1`.

To add custom error pages: uncomment `embed_templates "error_html/*"` and create `error_html/404.html.heex` and `500.html.heex`.

---

### `BlackboexWeb.ErrorJSON`

**File:** `controllers/error_json.ex`

Invoked by Phoenix for JSON error responses (`:api` pipeline). Returns:

```json
{"errors": {"detail": "<status message>"}}
```

To add a custom 422: add `def render("422.json", _assigns)` before the catch-all clause.

---

## Auth and Organization Hooks

Auth flow (UserAuth module, session management, token types): see `accounts/AGENTS.md § Auth Flow`.

SetOrganization hook (loads org + membership into scope at LiveView mount): see `plugs/AGENTS.md`.

---

## How to Add a New Controller

1. Create the module in `controllers/`:
   ```elixir
   defmodule BlackboexWeb.MyController do
     use BlackboexWeb, :controller

     @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
     def index(conn, _params) do
       render(conn, :index, page_title: "My Page")
     end
   end
   ```
   Every public function requires `@spec` (enforced by Dialyzer and Credo).

2. Create the HTML module if rendering templates:
   ```elixir
   defmodule BlackboexWeb.MyHTML do
     use BlackboexWeb, :html
     embed_templates "my_html/*"
   end
   ```

3. Add the route in `router.ex` inside the appropriate scope and pipeline.

4. Choose the right pipeline:
   - Public: `:browser` only.
   - Authenticated HTML: `:browser` + `:require_authenticated_user` + `:audit_context`.
   - Admin-only: add `:require_platform_admin` after `:require_authenticated_user`.
   - Webhook/external POST: `:api` only (no CSRF, no session).

5. Never call domain modules from templates — all data flows through context functions called from the controller action.

6. Never use `Repo.get!/2` with external data — use `Repo.get/2` + explicit pattern match on nil.

---

## Gotchas

- **User enumeration:** `UserSessionController.create/2` (password branch) does not distinguish "user not found" from "wrong password". Both return the same flash. Do not change this.

- **Webhook body:** `CacheBodyReader` must be configured as `body_reader` in `Plug.Parsers` at the endpoint. If removed, `WebhookController` always gets an empty raw body and all Stripe signatures fail.

- **Webhook idempotency:** `{:error, :already_processed}` must return 200. Stripe retries on non-2xx; returning 4xx/5xx for already-processed events causes infinite retries.

- **Session safety:** `current_scope` is always set after `fetch_current_scope_for_user` — either `%Scope{user: %User{}}` or `Scope.for_user(nil)`. Never pattern-match on `%Scope{}` without checking `.user`.

- **Sudo mode:** `update_password` asserts `true = Accounts.sudo_mode?(user)` — this raises `MatchError` if the window has passed (deliberate guard, not silent failure).

- **PublicApiController 404:** Both "org not found" and "api not found/unpublished/private" render the same 404. This is intentional — do not leak existence of non-public resources.

- **Remember-me inheritance:** Token rotation (reissuance) preserves the remember-me preference via `:user_remember_me` session flag without requiring the user to re-submit the form.
