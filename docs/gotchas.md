# Known Gotchas

Consolidated from 10 development phases. Organized by category.

## Security

| # | Problem | Fix |
|---|---------|-----|
| 1 | **IDOR** — `Repo.get(Schema, id)` without ownership check | Always verify resource belongs to current user/org. Pin match: `%{org_id: ^org_id}` |
| 2 | **Timing attacks** — comparing secrets with `==` | Use `Plug.Crypto.secure_compare/2` for all secret comparison |
| 3 | **Code injection in snippets** — interpolating user values into generated code | Use language-specific escaping. Never raw string interpolation |
| 4 | **SSRF** — `URI.parse("//evil.com")` passes scheme-only check | Validate BOTH `uri.scheme != nil AND uri.host != nil` |
| 5 | **LiveView event params** — unvalidated method, tab, language from client | Module-attr whitelists: `@valid_methods ~w(GET POST)` + guard clause |
| 6 | **Prompt injection** — code fences in user input break LLM prompt structure | Sanitize: replace triple backticks, cap metadata length |
| 7 | **Error message exposure** — `inspect(reason)` or `Exception.message(e)` to users | Generic messages for UI; log real errors with `Logger.warning` |
| 8 | **Atom safety** — `String.to_existing_atom/1` on external data | Use explicit Map lookup: `%{"free" => :free}` + `Map.get` |
| 9 | **Policy action pairs** — implementing `:api_publish` without `:api_unpublish` | Always add inverse action when adding any policy action |
| 10 | **XSS** — assuming HEEx escaping is always sufficient | Add explicit test with `<script>alert('xss')</script>` |

## Concurrency

| # | Problem | Fix |
|---|---------|-----|
| 1 | **LiveView blocking** — `send(self(), :heavy_work)` freezes UI | Use `Task.async/1` + `handle_info({ref, result})` + handle `{:DOWN, ...}` |
| 2 | **Task.async double-submit** — clicking twice overwrites ref, orphans first task | Guard: `%{assigns: %{loading: true}} = socket -> {:noreply, socket}` |
| 3 | **Stale task refs** — not clearing ref in all exit paths (success, error, DOWN) | Set `ref: nil` in every exit path consistently |
| 4 | **JSONB race condition** — concurrent array appends (TOCTOU) | `Ecto.Multi` with `SELECT ... FOR UPDATE` lock |
| 5 | **Plug.Conn process affinity** — using conn in Task/separate process | Call `module.call(conn, opts)` in request process only |
| 6 | **Task.Supervisor unbounded** — default `:infinity` max_children | Set explicit: `max_children: 1000` |
| 7 | **Version number race** — computing next version outside transaction | `SELECT MAX(version_number)` inside `Ecto.Multi` |

## Elixir/OTP

| # | Problem | Fix |
|---|---------|-----|
| 1 | **Struct in module attr** — `%__MODULE__{}` in attr fails (struct not defined yet) | Use keyword list + `struct!/2` at runtime |
| 2 | **defdelegate + defaults** — causes Dialyzer `:unknown_function` | Add to `.dialyzer_ignore.exs` |
| 3 | **Map update syntax** — `%{@attr \| key: val}` crashes on missing key | Use `Map.put(@attr, :key, val)` |
| 4 | **handle_event clause grouping** — separated clauses trigger warning | Keep all clauses of same name/arity adjacent |
| 5 | **rescue in anonymous fn** — bare `rescue` is syntax error | Use explicit `try do ... rescue ... end` inside fn body |
| 6 | **Credo cyclomatic > 9** — complex cond/case | Extract into function clauses (dispatch doesn't count toward complexity) |
| 7 | **SystemUniqueInteger** — can be negative | Use `System.unique_integer([:positive])` in fixtures |
| 8 | **Ecto.Multi.run callback** — must return `{:ok, value}` or `{:error, value}` | Wrap multi-value: `{:ok, {a, b}}` |
| 9 | **Regex line endings** — `\n` fails on `\r\n` | Use `[\r\n]` in all regex patterns |

## LiveView

| # | Problem | Fix |
|---|---------|-----|
| 1 | **`@attr` in HEEx** — resolves to assigns, not module attributes | Hardcode value or pass as explicit assign |
| 2 | **LiveComponent assigns** — not inherited from parent | Pass every required assign explicitly in component tag |
| 3 | **defp between callbacks** — "clauses should be grouped" warning | ALL public callbacks first, private helpers at bottom |
| 4 | **Stale assigns IDOR** — `Enum.find(assigns.list, &(&1.id == id))` | Verify ownership server-side: check `owner_id == current_owner_id` |

## Database

| # | Problem | Fix |
|---|---------|-----|
| 1 | **Cascade delete untested** — adding `on_delete: :delete_all` without test | Always test: create child, delete parent, verify child removed |
| 2 | **avg() returns Decimal** — schema expects Float | Convert: `Decimal.to_float/1` |
| 3 | **N+1 in workers** — computing p95 per-API in separate queries | Use `percentile_cont(...) filter (where ...)` in single GROUP BY |
| 4 | **String fields unbounded** — no length validation | `validate_length` for bounds, `validate_inclusion` for enums |
| 5 | **Numeric fields unchecked** — accept negative/zero | `validate_number(:rate_limit, greater_than: 0)` |
| 6 | **JSONB metadata size** — no validation on map size | `validate_change` with `map_size(value) > @max_keys` check |
| 7 | **fetch_query_params** — must call explicitly before accessing `conn.query_params` | Call `Plug.Conn.fetch_query_params/1` first |

## Billing/Stripe

| # | Problem | Fix |
|---|---------|-----|
| 1 | **Webhook idempotency order** — marking as processed BEFORE handling | Order: check → process → mark (only mark on success) |
| 2 | **Return 200 on failure** — Stripe doesn't retry 200s | Return 500 on real failures; 200 only for success/already_processed |
| 3 | **Missing Stripe secrets in prod** — silent failure | `runtime.exs`: `System.get_env("STRIPE_KEY") \|\| raise "missing..."` |
| 4 | **DateTime.from_unix!** — crashes on non-integer webhook data | Guard `is_integer/1` before calling |

## Testing

| # | Problem | Fix |
|---|---------|-----|
| 1 | **ExUnit module leak** — `Code.compile_string` with `use ExUnit.Case` | Use `SandboxCase` instead — no auto-registration |
| 2 | **UUID ordering** — not sequential, tests relying on insert order fail | Test count/membership, not position |
| 3 | **Empty test module** — returns `{:ok, []}` (false positive "all passed") | Check `all_test_fns == []` → return error |
| 4 | **Same-millisecond inserts** — `inserted_at` ordering unreliable | Don't assert position; assert membership |
| 5 | **Mox + async** — Mox mocks require `async: false` | Always set `async: false` in test modules using Mox |
| 6 | **Test fixture signatures** — calling with wrong arity | Grep existing usage before writing test setup |

## Infrastructure

| # | Problem | Fix |
|---|---------|-----|
| 1 | **Health check DB timeout** — hanging DB blocks all probes | Add `timeout: 5000` to health check SQL query |
| 2 | **Process.list performance** — O(n) per process, kills CPU on polling | Use `:erlang.statistics(:total_run_queue_lengths_all)` instead |
| 3 | **PromEx metric cardinality** — `api_id` as tag | Avoid high-cardinality tags; use rollup tables |
| 4 | **Timeout/heap from user input** — no upper cap | Apply: `min(user_value, @hard_cap)` on every limit |
| 5 | **Dynamic modules lost on restart** — Registry has no persistence | Registry reloads from DB on init; DynamicApiRouter has compile fallback |
| 6 | **Esbuild umbrella imports** — relative paths fail | Use NODE_PATH for cross-app imports |

## Umbrella/Project

| # | Problem | Fix |
|---|---------|-----|
| 1 | **SaladUI in umbrella** — needs manual `Component` module + config prefix | Create `BlackboexWeb.Component` manually |
| 2 | **phx.gen.auth** — must run from web app directory, not umbrella root | `cd apps/blackboex_web` first |
| 3 | **LetMe DSL formatter** — not recognized by default | Add `import_deps: [:let_me]` to `.formatter.exs` |
| 4 | **LetMe action atoms** — `object :api do action :update` compiles to `:api_update` | Use composed atom `:api_update`, not separate args |
| 5 | **Cross-app module visibility** — calling dep from wrong app warns | Create wrapper in domain app; call wrapper from web |
| 6 | **Backpex admin_changeset/3** — must be arity 3 with `_metadata` | Never use arity 2; Backpex won't call it |
| 7 | **Admin changeset field restriction** — don't reuse regular changeset | Create explicit cast for admin-editable fields only |
| 8 | **Audit logs read-only** — must not be editable via admin | Use `only: [:index, :show]` in Backpex router |
