# Contributing to Blackboex

This guide covers setup, development workflow, and how to submit a pull request.

## Prerequisites

- Elixir 1.19+ and OTP 28+
- PostgreSQL 16+
- Docker (for the local dev stack)

## Setup

```bash
git clone https://github.com/rodrigomarchi/blackboex.git
cd blackboex
cp .env.example .env   # Fill in at least SECRET_KEY_BASE, CLOAK_KEY, MAILER_API_KEY
make setup             # Docker + deps + DB
make server            # → http://localhost:4000
```

## Development Workflow

### TDD is mandatory

Write the test first, see it fail, then implement. Every pull request must include tests for new behaviour.

```bash
make test              # Full test suite
make test.web          # Web app only
make test.domain       # Domain app only
make test.failed       # Re-run only failed tests
```

### Lint before every commit

```bash
make lint              # mix format + credo + dialyzer
make precommit         # compile + format + test
```

All linter warnings must be resolved — including Credo `[D]` design warnings and Dialyzer warnings. Do not ignore or suppress warnings without a documented root cause.

### Zero-warning policy

- Never add `# credo:disable-for-this-file` or similar suppressions without justification
- Dialyzer warnings must be investigated, not silenced

## Code Style

- Every public function must have `@spec`
- LiveViews must be thin — delegate business logic to domain contexts
- Follow the **facade + Queries + sub-context** decomposition pattern (see `AGENTS.md`)
- Use `Blackboex.Schema` for all domain schemas (not `Ecto.Schema` directly)

## Submitting a Pull Request

1. Fork the repository and create a feature branch from `main`
2. Write tests first (TDD)
3. Implement your change
4. Run `make precommit` and ensure it passes cleanly
5. Update `AGENTS.md` if you added or changed modules, functions, or components
6. Open a PR against `main` with a clear description of what changed and why

## Questions?

Open a [GitHub Discussion](https://github.com/rodrigomarchi/blackboex/discussions) or a [GitHub Issue](https://github.com/rodrigomarchi/blackboex/issues).
