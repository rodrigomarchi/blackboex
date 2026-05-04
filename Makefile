.PHONY: help setup deps server stress-server iex routes \
       e2e e2e.stress e2e.full-stress \
       test test.unit test.integration test.liveview test.all test.cover \
       test.domain test.web test.failed test.file test.line \
       lint format format.check credo dialyzer precommit compile \
       assets.setup assets.build assets.deploy \
       clean clean.deps clean.build clean.all \
       deps.tree deps.update deps.unlock \
       db.setup db.create db.migrate db.rollback db.reset db.seed db.gen.migration \
       docker.up docker.down docker.ps docker.logs docker.reset docker.stop \
       observability observability.down

DOMAIN_APP = apps/blackboex
WEB_APP    = apps/blackboex_web

help: ## Show this help
	@grep -E '^[a-zA-Z_\.-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

# ── Docker ─────────────────────────────────────────────────────────────
docker.up: ## Start PostgreSQL containers (dev + test)
	docker compose up -d

docker.down: ## Stop and remove PostgreSQL containers
	docker compose down

docker.stop: ## Stop PostgreSQL containers (keep data)
	docker compose stop

docker.ps: ## Show running container status
	docker compose ps

docker.logs: ## Tail PostgreSQL container logs
	docker compose logs -f

docker.reset: ## Destroy containers and volumes (fresh start)
	docker compose down -v

# ── Observability ─────────────────────────────────────────────────────
observability: ## Start observability stack (Prometheus, Grafana, Loki, Tempo)
	docker compose -f docker-compose.observability.yml up -d

observability.down: ## Stop observability stack
	docker compose -f docker-compose.observability.yml down

# ── Setup ──────────────────────────────────────────────────────────────
setup: docker.up deps db.setup ## First-time project setup (docker + deps + db + assets)
	@echo ""
	@echo "Setup complete. Open http://localhost:4000 to complete first-run setup."
	@echo ""

deps: ## Install Elixir dependencies
	mix deps.get

# ── Database ───────────────────────────────────────────────────────────
db.setup: ## Create database, run migrations, and seed
	mix ecto.setup

db.create: ## Create the database
	mix ecto.create

db.migrate: ## Run pending migrations
	mix ecto.migrate

db.rollback: ## Rollback the last migration
	mix ecto.rollback

db.reset: ## Drop, create, migrate, and seed the database
	mix ecto.reset

db.seed: ## Run seed script
	mix run $(DOMAIN_APP)/priv/repo/seeds.exs

db.gen.migration: ## Generate a migration (usage: make db.gen.migration NAME=create_foo)
	mix ecto.gen.migration $(NAME)

# ── Server ─────────────────────────────────────────────────────────────
server: ## Start Phoenix dev server at localhost:4000
	mix phx.server

stress-server: ## Start Phoenix without code reloader + high fd/db limits (for stress tests)
	ulimit -n 65536 && DISABLE_CODE_RELOAD=true DB_POOL_SIZE=200 mix phx.server

iex: ## Start Phoenix dev server inside IEx
	iex -S mix phx.server

routes: ## List all application routes
	mix phx.routes BlackboexWeb.Router

# ── Tests ──────────────────────────────────────────────────────────────
test: ## Run full test suite
	mix test

test.unit: ## Run unit tests only
	cd $(DOMAIN_APP) && mix test --only unit

test.integration: ## Run integration tests only
	cd $(DOMAIN_APP) && mix test --only integration

test.liveview: ## Run LiveView tests only
	cd $(WEB_APP) && mix test --only liveview

test.all: ## Run ALL tests (including slow tags)
	mix test --include integration --include liveview --include slow

test.cover: ## Run tests with coverage report
	mix test --cover

test.domain: ## Run domain app tests only
	cd $(DOMAIN_APP) && mix test

test.web: ## Run web app tests only
	cd $(WEB_APP) && mix test

test.failed: ## Re-run only previously failed tests
	mix test --failed

test.file: ## Run a specific test file (usage: make test.file FILE=path/to/test.exs)
	mix test $(FILE)

test.line: ## Run a specific test by file:line (usage: make test.line TARGET=path/to/test.exs:42)
	mix test $(TARGET)

# ── E2E Scripts ────────────────────────────────────────────────────────
e2e: ## Run full e2e suite (requires make server)
	mix run apps/blackboex/priv/scripts/e2e_flows.exs

e2e.stress: ## Run normal + per-flow stress (requires make stress-server)
	ulimit -n 65536 && DISABLE_CODE_RELOAD=true DB_POOL_SIZE=200 mix run apps/blackboex/priv/scripts/e2e_flows.exs -- --stress

e2e.full-stress: ## Run all flows in parallel max stress (requires make stress-server)
	ulimit -n 65536 && DISABLE_CODE_RELOAD=true DB_POOL_SIZE=200 mix run apps/blackboex/priv/scripts/e2e_flows.exs -- --full-stress --requests 200 --concurrency 50

# ── Static Analysis ───────────────────────────────────────────────────
lint: format.check credo dialyzer ## Run all static analysis checks

format: ## Auto-format all source files
	mix format

format.check: ## Check formatting without modifying files
	mix format --check-formatted

credo: ## Run Credo linter (strict mode)
	mix credo --strict

dialyzer: ## Run Dialyzer type checker
	mix dialyzer

precommit: ## Run pre-commit pipeline (compile + format + test)
	mix precommit

compile: ## Compile with warnings as errors
	mix compile --warnings-as-errors

# ── Assets ─────────────────────────────────────────────────────────────
assets.setup: ## Install esbuild and tailwind
	mix esbuild.install --if-missing
	mix tailwind.install --if-missing

assets.build: ## Build JS/CSS assets for development
	mix esbuild blackboex_web
	mix tailwind blackboex_web

assets.deploy: ## Build and minify assets for production
	mix assets.deploy

# ── Cleanup ────────────────────────────────────────────────────────────
clean: ## Clean compiled artifacts
	mix clean

clean.deps: ## Remove all fetched dependencies
	mix deps.clean --all

clean.build: ## Remove _build directory
	rm -rf _build

clean.all: clean.build clean.deps ## Full clean (build + deps)
	rm -rf $(WEB_APP)/priv/static/assets

# ── Introspection ─────────────────────────────────────────────────────
deps.tree: ## Show dependency tree
	mix deps.tree

deps.update: ## Update all dependencies
	mix deps.update --all

deps.unlock: ## Remove unused dependencies from lock file
	mix deps.unlock --unused
