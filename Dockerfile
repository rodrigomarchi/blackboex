# BlackBoex production Dockerfile
# Multi-stage build: build -> runtime
#
# Build:
#   docker build -t blackboex .
#
# Run:
#   docker run -p 4000:4000 \
#     -e DATABASE_URL=ecto://... \
#     -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
#     -e STRIPE_SECRET_KEY=... \
#     -e STRIPE_WEBHOOK_SECRET=... \
#     -e MAILER_API_KEY=... \
#     blackboex

ARG ELIXIR_VERSION=1.19.3
ARG OTP_VERSION=28.0.1
ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# =============================================================================
# Build stage
# =============================================================================
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
COPY apps/blackboex/mix.exs apps/blackboex/mix.exs
COPY apps/blackboex_web/mix.exs apps/blackboex_web/mix.exs
COPY config/config.exs config/prod.exs config/runtime.exs config/

RUN mix deps.get --only $MIX_ENV && \
    mkdir config

# Copy compile-time config files (already copied above, ensure deps compile)
RUN mix deps.compile

# Copy application source
COPY apps/blackboex/lib apps/blackboex/lib
COPY apps/blackboex/priv apps/blackboex/priv
COPY apps/blackboex_web/lib apps/blackboex_web/lib
COPY apps/blackboex_web/priv apps/blackboex_web/priv
COPY apps/blackboex_web/assets apps/blackboex_web/assets

# Compile the release
RUN mix compile

# Build assets (esbuild + tailwind)
RUN mix assets.deploy

# Build the release
COPY rel rel
RUN mix release blackboex

# =============================================================================
# Runtime stage
# =============================================================================
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod"

# Copy the release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/blackboex ./

USER nobody

# Set runtime ENV defaults
ENV PHX_SERVER=true
ENV PORT=4000

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:4000/health/live || exit 1

CMD ["/app/bin/blackboex", "start"]
