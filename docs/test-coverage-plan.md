# Test Coverage Improvement Plan

**Date:** 2026-04-05
**Current Coverage:** 41.89% | **Target:** 90%
**Philosophy:** Tests that expose hidden bugs through edge/corner cases. Coverage is a consequence, not the goal.

---

## Current State Analysis

### Coverage by App

| App | Estimated Coverage | Notes |
|-----|-------------------|-------|
| `blackboex` (domain) | ~45% | Core logic gaps in Agent, LLM, CodeGen |
| `blackboex_web` (web) | ~55% | LiveViews and some plugs under-tested |

### Test Infrastructure Available

- **Mox** mocks: `Blackboex.LLM.ClientMock`, `Blackboex.Billing.StripeClientMock`
- **ExMachina** factory: `Blackboex.Factory` (0% coverage itself — needs fixtures)
- **DataCase** template: SQL sandbox for async DB tests
- **ConnCase** template: Phoenix endpoint testing
- **Fixtures**: `Blackboex.AccountsFixtures` for user/org setup

---

## Module Priority Order (Sequential Execution)

Modules ordered by: (1) bug exposure potential, (2) complexity, (3) coverage gap size.

### Phase 1: Pure Functions & Parsers (Low Dependencies, High Bug Exposure)

These modules are pure or near-pure — no GenServers, no DB, no external APIs. Easiest to test thoroughly with edge cases and the most likely to expose hidden parsing/logic bugs.

---

#### Task 1: `Blackboex.CodeGen.UnifiedPrompts` (0% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/code_gen/unified_prompts.ex` (94 LOC)
**Test file:** `apps/blackboex/test/blackboex/code_gen/unified_prompts_test.exs` (NEW)
**Public API:**
- `build_fix_code_prompt/2` — prompt for fixing compilation errors
- `build_fix_test_prompt/3` — prompt for fixing test failures
- `parse_response/1` — extracts code blocks from LLM response
- `parse_search_replace_blocks/1` — parses SEARCH/REPLACE edit format
- `parse_test_fix_edits/1` — parses ---CODE---/---TESTS--- with SEARCH/REPLACE
- `parse_code_and_tests/1` — legacy full-code parser

**Edge Cases to Test:**
- [ ] Empty string input to all parsers
- [ ] Malformed SEARCH/REPLACE blocks (missing markers, extra whitespace, nested code fences)
- [ ] Code containing triple backticks (fence breakout — security concern per phase08 gotchas)
- [ ] Multiple code blocks in single response
- [ ] Mixed valid/invalid blocks
- [ ] Unicode/special characters in code
- [ ] Windows line endings (`\r\n`) vs Unix (`\n`) — known issue per phase08 gotchas
- [ ] Extremely long input strings
- [ ] Prompt injection attempts in code content (code fence breakout)
- [ ] Missing ---CODE--- or ---TESTS--- sections
- [ ] Empty sections between markers

**Bugs to Probe:**
- Regex `\r\n` handling (documented gotcha)
- Code fence breakout in parsed content
- Off-by-one in block extraction

---

#### Task 2: `Blackboex.Agent.FixPrompts` (20.9% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/agent/fix_prompts.ex` (272 LOC)
**Test file:** `apps/blackboex/test/blackboex/agent/fix_prompts_test.exs` (NEW)
**Public API:**
- `fix_compilation/3` — builds compilation fix prompt
- `fix_lint/3` — builds lint fix prompt
- `fix_tests/4` — builds test fix prompt
- `edit_code/4` — builds code edit prompt
- `parse_search_replace_blocks/1` — SEARCH/REPLACE parser
- `parse_test_fix_edits/1` — CODE/TESTS parser
- `parse_code_and_tests/1` — legacy parser

**Edge Cases to Test:**
- [ ] Empty error lists for fix_compilation/fix_lint
- [ ] Very long error messages (truncation behavior?)
- [ ] Error messages containing Elixir code (escaping)
- [ ] Nil/empty code inputs
- [ ] SEARCH block that doesn't match any code (partial match)
- [ ] REPLACE block with empty replacement
- [ ] Overlapping SEARCH/REPLACE blocks
- [ ] Duplicate SEARCH blocks
- [ ] Prompt template variable injection
- [ ] Code with module attributes and complex AST

**Bugs to Probe:**
- Shared parsing logic with UnifiedPrompts — are they consistent?
- Error message content leaking into prompts unsanitized
- Parser divergence between the two modules

---

#### Task 3: `Blackboex.Apis.DiffEngine` (43.3% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/apis/diff_engine.ex` (79 LOC)
**Test file:** `apps/blackboex/test/blackboex/apis/diff_engine_test.exs` (EXISTS — expand)
**Public API:**
- `compute_diff/2` — computes diff between two code strings
- `format_diff_summary/1` — formats diff for display
- `apply_search_replace/2` — applies SEARCH/REPLACE edits to code

**Edge Cases to Test:**
- [ ] Identical strings (no diff)
- [ ] One or both strings empty
- [ ] Binary/non-UTF8 content
- [ ] Very large files (performance)
- [ ] Whitespace-only changes
- [ ] apply_search_replace where SEARCH doesn't exist in code
- [ ] apply_search_replace with multiple matches (which one wins?)
- [ ] apply_search_replace with overlapping regions
- [ ] Trailing newline differences
- [ ] Tab vs spaces differences

**Bugs to Probe:**
- SEARCH/REPLACE with ambiguous matches
- Whitespace sensitivity in search matching
- Order of application for multiple edits

---

#### Task 4: `Blackboex.CodeGen.Linter` (1.8% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/code_gen/linter.ex` (370 LOC)
**Test file:** `apps/blackboex/test/blackboex/code_gen/linter_test.exs` (NEW)
**Public API:**
- `run_all/1` — runs all checks
- `check_format/1` — formatting check
- `auto_format/1` — auto-formats code
- `check_credo/1` — credo-style checks (line length, specs, docs, fn length, nesting)

**Edge Cases to Test:**
- [ ] Empty module
- [ ] Module with only `use` directives
- [ ] Function exactly at 40-line limit vs 41 lines
- [ ] Line exactly at 120 chars vs 121
- [ ] Nesting at exactly 4 levels vs 5
- [ ] Private function without @spec (should NOT warn)
- [ ] Public function without @spec (MUST warn)
- [ ] Heredoc strings that look like long lines
- [ ] Multi-clause functions (counted separately or together?)
- [ ] Macros (def vs defmacro treatment)
- [ ] Invalid Elixir code (syntax error handling)
- [ ] Code with comments containing @spec-like patterns
- [ ] Deeply nested `with` statements
- [ ] Pattern matching in function heads with guards

**Bugs to Probe:**
- AST traversal missing edge cases in Elixir syntax
- False positives on heredocs/strings
- Nesting count in `with` vs `case` vs `if`
- @spec detection when spec is separated from function by comments

---

### Phase 2: Stateful Components (GenServers, State Machines)

These require process management but no external dependencies. High value for exposing concurrency and state bugs.

---

#### Task 5: `Blackboex.LLM.CircuitBreaker` (16.3% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/llm/circuit_breaker.ex` (199 LOC)
**Test file:** `apps/blackboex/test/blackboex/llm/circuit_breaker_test.exs` (NEW)
**Public API:**
- `start_link/1`, `allow?/1`, `record_success/1`, `record_failure/1`, `get_state/1`, `reset/1`

**State Machine:**
```
closed --[5 failures in 60s]--> open --[30s timeout]--> half_open
half_open --[2 successes]--> closed
half_open --[1 failure]--> open
```

**Edge Cases to Test:**
- [ ] Rapid failures at exact threshold (5th failure triggers open)
- [ ] Failures spread across window boundary (4 old + 1 new — should NOT trip)
- [ ] Window expiration (failures expire after 60s)
- [ ] half_open: exactly 2 successes to close
- [ ] half_open: failure after 1 success (resets success count?)
- [ ] Concurrent calls during state transitions
- [ ] reset/1 from each state
- [ ] allow?/1 during state transition race
- [ ] GenServer crash and restart (state loss)
- [ ] Multiple providers (independent circuit breakers)
- [ ] Timer accuracy under load

**Bugs to Probe:**
- Race condition: allow? returns true, but state changes to open before call completes
- Failure window implementation: sliding window vs fixed window?
- Timer-based recovery: what if GenServer is slow to process messages?
- State not persisted — crash during half_open loses recovery progress

---

#### Task 6: `Blackboex.Testing.TestFormatter` (0% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/testing/test_formatter.ex` (98 LOC)
**Test file:** `apps/blackboex/test/blackboex/testing/test_formatter_test.exs` (NEW)
**Public API:**
- `get_results/1` — retrieves collected test results

**GenServer Events:**
- `{:test_finished, test}` — collects test result
- `{:suite_finished, _}` — marks suite as done
- `{:module_started, _}` — module boundary

**Edge Cases to Test:**
- [ ] Empty suite (no tests)
- [ ] get_results before any tests run
- [ ] get_results after suite_finished
- [ ] Test with nil failure
- [ ] Test with very long error message
- [ ] Concurrent test_finished events
- [ ] ExUnit state atoms: :passed, :failed, :excluded, :skipped
- [ ] Unknown/unexpected ExUnit event
- [ ] Error formatting with nested exceptions
- [ ] format_status/1 OTP 26+ callback

**Bugs to Probe:**
- Memory leak if results list grows unbounded
- Error formatting crash on unexpected exception structure
- GenServer timeout on get_results with large result set

---

#### Task 7: `Blackboex.Apis.Registry` (41.6% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/apis/registry.ex` (278 LOC)
**Test file:** `apps/blackboex/test/blackboex/apis/registry_test.exs` (EXISTS — expand)
**Public API:**
- `start_link/1`, `register/1`, `lookup/1`, `lookup_by_path/1`, `unregister/1`, `clear/0`, `shutting_down?/0`, `shutdown/0`

**Edge Cases to Test:**
- [ ] Register same API twice (idempotent? error?)
- [ ] Lookup non-existent API
- [ ] Lookup by path with trailing slash vs without
- [ ] Unregister non-existent entry
- [ ] Register during shutdown
- [ ] Concurrent register/lookup/unregister
- [ ] ETS table ownership on GenServer restart
- [ ] clear/0 followed by immediate lookup
- [ ] Path collision (two APIs with same path)
- [ ] Very long path strings
- [ ] Path with special characters/encoding

**Bugs to Probe:**
- ETS table leak on GenServer crash
- Race between shutdown flag and register
- Path normalization inconsistencies

---

### Phase 3: Database-Dependent Modules

Require seeded data but expose query logic bugs and data integrity issues.

---

#### Task 8: `Blackboex.Policy` (12.5% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/policy.ex` (144 LOC)
**Test file:** `apps/blackboex/test/blackboex/policy_test.exs` (EXISTS — expand)
**Roles:** owner, admin, member
**Objects:** organization, api, api_key, membership

**Edge Cases to Test:**
- [ ] Every role x action x object combination (exhaustive matrix)
- [ ] authorize_and_track/3 telemetry emission
- [ ] Nil user/subject
- [ ] User without organization membership
- [ ] Cross-organization access attempt (IDOR)
- [ ] Action not defined in policy (unknown action)
- [ ] Object not defined in policy (unknown object)
- [ ] Role escalation: member trying owner actions
- [ ] authorize_and_track with telemetry handler crash (resilience)

**Bugs to Probe:**
- Missing action pairs (per phase07 gotchas)
- LetMe DSL edge cases
- Telemetry safe_execute wrapping

---

#### Task 9: `Blackboex.Apis.DashboardQueries` (0% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/apis/dashboard_queries.ex` (316 LOC)
**Test file:** `apps/blackboex/test/blackboex/apis/dashboard_queries_test.exs` (NEW)
**Public API:**
- `get_org_summary/1` — org-level stats
- `list_apis_with_stats/2` — API list with 24h stats
- `search_apis/2` — ilike search
- `get_dashboard_metrics/2` — time-series metrics
- `get_llm_usage_series/2` — LLM usage time-series

**Edge Cases to Test:**
- [ ] Empty organization (no APIs, no invocations)
- [ ] Organization with APIs but no invocations
- [ ] Invocations exactly at 24h boundary
- [ ] Time zone edge cases in daily aggregation
- [ ] Very large dataset (query performance)
- [ ] SQL injection via search term (ilike escaping)
- [ ] search_apis with special chars: `%`, `_`, `\`
- [ ] get_dashboard_metrics with future dates
- [ ] get_dashboard_metrics with period spanning DST change
- [ ] Null/zero values in aggregations (avg of empty set)
- [ ] Decimal precision in latency calculations
- [ ] Organization with exactly 5 APIs (top 5 boundary)
- [ ] LLM usage with zero tokens but non-zero cost

**Bugs to Probe:**
- ilike injection via `%` and `_` characters
- Division by zero in average calculations
- Decimal to float cast (per phase10 gotchas)
- N+1 queries in list_apis_with_stats
- Date boundary off-by-one

---

#### Task 10: `Blackboex.CodeGen.Sandbox` (46.7% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/code_gen/sandbox.ex` (131 LOC)
**Test file:** `apps/blackboex/test/blackboex/code_gen/sandbox_test.exs` (EXISTS — expand)
**Public API:**
- `execute/1` — executes code in sandboxed process
- `execute_plug/1` — executes Plug handler in sandbox

**Edge Cases to Test:**
- [ ] Code that raises an exception
- [ ] Code that exits the process
- [ ] Code with infinite loop (timeout handling)
- [ ] Code attempting to access filesystem
- [ ] Code attempting network access
- [ ] Code attempting to spawn processes
- [ ] Code using System module (dangerous ops)
- [ ] Code with memory bomb (very large data structures)
- [ ] Code using Code.eval_string (nested eval)
- [ ] Code referencing undefined modules
- [ ] Code with compile-time side effects
- [ ] Empty code string
- [ ] Valid code returning various types (map, list, tuple, binary)
- [ ] Code exceeding heap size limit (per phase08 gotchas)
- [ ] Plug handler returning non-standard responses

**Bugs to Probe:**
- Sandbox escape via Code.compile_string (phase08 gotcha)
- Process isolation: can sandboxed code affect parent?
- Timeout race condition: result returned after timeout
- Memory limit enforcement accuracy

---

### Phase 4: External Integration (Mocked)

Modules that talk to external services. Use existing Mox mocks.

---

#### Task 11: `Blackboex.LLM.ReqLLMClient` (0% -> 80%+)

**Source:** `apps/blackboex/lib/blackboex/llm/req_llm_client.ex` (71 LOC)
**Test file:** `apps/blackboex/test/blackboex/llm/req_llm_client_test.exs` (NEW)

**Note:** This is the real client implementing `ClientBehaviour`. Tests should verify the contract, not mock the behavior (it IS the behavior). Use Req test adapters or test against the mock at the boundary.

**Edge Cases to Test:**
- [ ] Successful text generation
- [ ] API error response (rate limit, auth failure, server error)
- [ ] Timeout on LLM call
- [ ] Malformed response from API
- [ ] Stream interruption mid-response
- [ ] Empty prompt
- [ ] Very long prompt (token limit)
- [ ] Usage tracking accuracy (tokens in/out)

**Bugs to Probe:**
- Error response structure mismatch
- Stream cleanup on error
- Default model/temperature override behavior

---

#### Task 12: `Blackboex.Billing.StripeClient.Live` (0% -> 80%+)

**Source:** `apps/blackboex/lib/blackboex/billing/stripe_client/live.ex` (55 LOC)
**Test file:** `apps/blackboex/test/blackboex/billing/stripe_client/live_test.exs` (NEW)

**Note:** Uses existing `StripeClientMock`. Tests verify contract compliance and error mapping.

**Edge Cases to Test:**
- [ ] Successful checkout session creation
- [ ] Successful portal session creation
- [ ] Successful subscription retrieval
- [ ] Stripe API returns error
- [ ] Invalid webhook signature
- [ ] Nil/empty params
- [ ] Webhook event with unknown type
- [ ] construct_webhook_event with tampered payload

**Bugs to Probe:**
- Error tuple format consistency with behaviour
- Webhook signature timing attack (per phase07 gotchas)
- Missing fields in Stripe response mapping

---

### Phase 5: Complex Orchestrators

These are the largest, most complex modules. Tests require extensive mocking and scenario building.

---

#### Task 13: `Blackboex.Agent.KickoffWorker` (0% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/agent/kickoff_worker.ex` (108 LOC)
**Test file:** `apps/blackboex/test/blackboex/agent/kickoff_worker_test.exs` (NEW)

**Edge Cases to Test:**
- [ ] Happy path: creates conversation, run, starts session
- [ ] Missing api_id in job args
- [ ] Non-existent api_id
- [ ] Conversation creation failure
- [ ] Run creation failure
- [ ] Session start failure (GenServer fails to start)
- [ ] PubSub broadcast verification
- [ ] Backoff schedule correctness: [60, 120, 300, 600]
- [ ] Timeout value: 7 minutes
- [ ] Concurrent executions for same API
- [ ] Job args with extra/unexpected fields

**Bugs to Probe:**
- Partial failure: conversation created but run fails (cleanup?)
- PubSub broadcast before session actually starts
- Race condition: two kickoff workers for same API

---

#### Task 14: `Blackboex.Agent.Session` (60.6% -> 90%+)

**Source:** `apps/blackboex/lib/blackboex/agent/session.ex` (802 LOC)
**Test file:** `apps/blackboex/test/blackboex/agent/session_test.exs` (EXISTS — expand)

**Edge Cases to Test (focus on uncovered paths):**
- [ ] Session timeout handling
- [ ] LLM call failure mid-session
- [ ] Multiple concurrent messages to same session
- [ ] Session recovery after crash (per RecoveryWorker)
- [ ] Max iteration limit reached
- [ ] PubSub broadcast for each state change
- [ ] Graceful shutdown during active generation
- [ ] Memory pressure during long sessions
- [ ] Invalid state transitions
- [ ] Event sourcing: all events persisted correctly

**Bugs to Probe:**
- Task.async race conditions (phase06 gotcha)
- State inconsistency after LLM timeout
- Event ordering under concurrent updates

---

#### Task 15: `Blackboex.Agent.CodePipeline` (28% -> 80%+)

**Source:** `apps/blackboex/lib/blackboex/agent/code_pipeline.ex` (947 LOC)
**Test file:** `apps/blackboex/test/blackboex/agent/code_pipeline_test.exs` (EXISTS — expand)

**Edge Cases to Test (focus on uncovered paths):**
- [ ] Full generation cycle: code -> compile -> lint -> test
- [ ] Compilation failure with fix retry
- [ ] Lint failure with fix retry
- [ ] Test failure with fix retry
- [ ] Max retry limit reached (gives up)
- [ ] LLM returns unparseable response
- [ ] Streaming interruption
- [ ] Empty code generation
- [ ] Code that compiles but fails lint
- [ ] Code that passes lint but fails tests
- [ ] All steps pass on first try (happy path)

**Bugs to Probe:**
- Fix cycle infinite loop (bounded?)
- State mutation between retries
- Error message propagation through pipeline stages

---

#### Task 16: `Blackboex.CodeGen.UnifiedPipeline` (0% -> 80%+)

**Source:** `apps/blackboex/lib/blackboex/code_gen/unified_pipeline.ex` (727 LOC)
**Test file:** `apps/blackboex/test/blackboex/code_gen/unified_pipeline_test.exs` (NEW)

**Edge Cases to Test:**
- [ ] validate_and_test happy path
- [ ] run_for_edit with streaming
- [ ] generate_edit_only returns without validation
- [ ] validate_on_save without LLM retry
- [ ] Compilation failure in validation loop
- [ ] Lint failure in validation loop
- [ ] Test generation failure
- [ ] Test run failure
- [ ] Fix cycle: code fix -> recompile -> relint
- [ ] Max validation iterations
- [ ] LLM streaming error mid-generation
- [ ] DiffEngine integration: edit application failure

**Bugs to Probe:**
- Validation loop infinite retry
- State leakage between validation steps
- Streaming callback error handling
- DocGenerator failure (should it block?)

---

### Phase 6: Web Layer (LiveViews with low coverage)

Focus on LiveViews and plugs with coverage < 50%.

---

#### Task 17: `BlackboexWeb.Plugs.DynamicApiRouter` (47.9%)

**Test file:** `apps/blackboex_web/test/blackboex_web/plugs/dynamic_api_router_test.exs` (expand)

**Edge Cases:** Path traversal, missing routes, method mismatch, content-type negotiation, oversized request body.

---

#### Task 18: `BlackboexWeb.ApiLive.Edit.*` (45-55% range)

Multiple LiveView modules: RunLive, InfoLive, ChatLive, Shared, VersionsLive.

**Edge Cases:** Socket disconnection, concurrent edits, stale state, PubSub message ordering, handle_event with invalid params.

---

## Execution Rules

1. **Sequential only** — one module at a time, complete before moving to next
2. **TDD approach** — write test, see it fail, verify the assertion makes sense
3. **Read source first** — understand the implementation before writing tests
4. **Consult AGENTS.md** — read the relevant AGENTS.md for each module's context
5. **Run `make test` after each module** — ensure no regressions
6. **Run `make lint` after each module** — no warnings
7. **Edge cases over happy paths** — prioritize corner cases that expose real bugs
8. **Document discoveries** — if a test exposes a real bug, note it in this file

---

## Bug Discovery Log

_(To be filled during test development)_

| Module | Bug Description | Severity | Fixed? |
|--------|----------------|----------|--------|
| Agent.FixPrompts | `parse_search_replace_blocks/1` fails with `\r\n` (Windows line endings). Regex uses literal `\n` which doesn't match `\r\n`. LLMs can return Windows-style line endings. Fix: normalize input or use `[\r\n]+` in regex. | Medium | No |
| CodeGen.Sandbox | `execute_plug/3` watchdog uses `Process.exit(target, :kill)` which is un-trappable. The `catch :exit, :killed` in the caller never fires — the process simply dies. In production this kills the HTTP process (Bandit stream owner). Should use `:brutal_kill` via a Task wrapper instead, or switch to a similar pattern as `execute/3` (Task.Supervisor + yield). | High | No |
| DynamicApiRouter | `resolve_api/2` missing `{:error, :shutting_down}` clause — the `dispatch/4` shutdown branch was dead code. Registry returns `{:error, :shutting_down}` but `resolve_api` only matched `{:error, :not_found}`, causing a `CaseClauseError` crash. | High | Yes |

---

## Progress Tracker

| # | Module | Status | Coverage Before | Coverage After | Bugs Found |
|---|--------|--------|----------------|----------------|------------|
| 1 | CodeGen.UnifiedPrompts | DONE | 0% | 32 tests | 0 |
| 2 | Agent.FixPrompts | DONE | 20.9% | 56 tests | 1 (\r\n bug) |
| 3 | Apis.DiffEngine | DONE | 43.3% | 28 tests | 0 |
| 4 | CodeGen.Linter | DONE | 1.8% | 42 tests | 0 |
| 5 | LLM.CircuitBreaker | DONE | 16.3% | 21 tests | 0 |
| 6 | Testing.TestFormatter | DONE | 0% | 18 tests | 0 |
| 7 | Apis.Registry | DONE | 41.6% | 21 tests | 0 |
| 8 | Policy | DONE | 12.5% | 20 tests | 0 |
| 9 | Apis.DashboardQueries | DONE | 0% | 25 tests | 0 |
| 10 | CodeGen.Sandbox | DONE | 46.7% | 14 tests | 1 (execute_plug kill bug) |
| 11 | LLM.ReqLLMClient | DONE | 0% | 4 tests | 0 (thin wrapper) |
| 12 | Billing.StripeClient.Live | DONE | 0% | 5 tests | 0 (thin wrapper) |
| 13 | Agent.KickoffWorker | DONE | 0% | 10 tests | 0 |
| 14 | Agent.Session | DONE | 60.6% | 24 tests | 0 |
| 15 | Agent.CodePipeline | DONE | 28% | 11 tests | 0 |
| 16 | CodeGen.UnifiedPipeline | DONE | 0% | 18 tests | 0 |
| 17 | Plugs.DynamicApiRouter | DONE | 47.9% | 20 tests | 1 (shutdown dead code) |
| 18 | ApiLive.Edit.* | TODO | ~50% | | |
