# Workspace image for FaleCom development.
#
# - Ruby 4.0.2 (matches .ruby-version)
# - Node LTS baked in so Vite works for CLI users too (VS Code devcontainer
#   features add another copy, which is harmless).
# - postgresql-client for psql against the postgres service.
# - bundler + standard pre-installed so first-time `bundle install` is fast.

FROM ruby:4.0.2-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    libpq-dev \
    libyaml-dev \
    postgresql-client \
    pkg-config \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

# Node LTS via NodeSource (needed for Vite in Phase 1B).
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Bundler prebaked; standard is installed via bundle install from the lockfile.
RUN gem install bundler:2.5.23

WORKDIR /workspaces/falecom

# Container runs as root for simplicity (no chown issues with mounted volumes).
# Do not change to a non-root user without updating volume permissions accordingly.
CMD ["sleep", "infinity"]
