# BlackBoex Development Guidelines

NUNCA fazer commit sem o usuário pedir explicitamente. Sempre esperar a instrução 'fazer o commit' ou similar antes de executar git commit.

## Active Technologies

- Elixir 1.19+ / OTP 28+ + Phoenix 1.8+, Phoenix LiveView 1.1+, Ecto 3.x
- PostgreSQL 16+ via Ecto
- Tailwind CSS + esbuild for asset bundling (no npm for build)
- SaladUI component library
- Bandit HTTP server

## Project Structure

```text
apps/
  blackboex/           # Domain (pure Elixir, zero Phoenix deps)
    lib/blackboex/
    priv/repo/migrations/
    test/
  blackboex_web/       # Web layer (Phoenix + LiveView)
    lib/blackboex_web/
    assets/
    test/
```

## Commands

```bash
make help                     # Show all available Makefile targets
make setup                    # First-time setup (docker + deps + db)
make server                   # Dev server (localhost:4000)
make test                     # Full test suite
make lint                     # All static analysis (format + credo + dialyzer)
make precommit                # compile + format + test
```

## Code Style

- Elixir: Follow standard conventions, `mix format` enforced
- Every public function MUST have `@spec`
- LiveViews MUST be thin — delegate to domain contexts
- Test tags: `@tag :unit`, `@tag :integration`, `@tag :liveview`
- Credo strict mode enforced
- Dialyzer from day one
