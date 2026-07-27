# tauceti worker environment — runs the loop in host mode (the container IS the sandbox),
# using both Codex and Claude via `--agent auto`. Builds for the host arch (arm64 or amd64).
# Subscription credentials are file-based on Linux and persist in named volumes.
# A dedicated Claude refresher owns refresh-token rotation (see docker-compose.yml).
FROM node:22-bookworm

# System deps: git, jq (tauceti), a C toolchain (Lean), ripgrep (Claude Code), and the gh CLI.
RUN apt-get update && apt-get install -y --no-install-recommends \
  git curl ca-certificates jq build-essential ripgrep \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# Agent CLIs. Subscription auth (Claude Max / ChatGPT) happens at runtime, into mounted volumes.
RUN npm install -g @anthropic-ai/claude-code @openai/codex

# Lean toolchains are shared container infrastructure, not per-worker HOME state. Install Elan's
# mutable state under /opt/elan, but copy its proxy executables to /usr/local/bin so they remain
# discoverable after TauCetiWorker replaces HOME and an agent starts a login shell. Install uv in
# the same home-independent executable directory.
ENV ELAN_HOME=/opt/elan \
  PYTHONUNBUFFERED=1
RUN set -eux; \
  curl -fsSL https://elan.lean-lang.org/elan-init.sh \
  | sh -s -- -y --default-toolchain none --no-modify-path; \
  for tool in "$ELAN_HOME"/bin/*; do \
  install -m 0755 "$tool" "/usr/local/bin/$(basename "$tool")"; \
  done; \
  curl -LsSf https://astral.sh/uv/install.sh \
  | env UV_UNMANAGED_INSTALL=/usr/local/bin sh; \
  mkdir -p /tmp/tauceti-worker-home; \
  env HOME=/tmp/tauceti-worker-home bash -lc 'test "$ELAN_HOME" = /opt/elan'; \
  env HOME=/tmp/tauceti-worker-home bash -lc 'test "$(command -v elan)" = /usr/local/bin/elan'; \
  env HOME=/tmp/tauceti-worker-home bash -lc 'test "$(command -v lake)" = /usr/local/bin/lake'; \
  env HOME=/tmp/tauceti-worker-home bash -lc 'test "$(command -v lean)" = /usr/local/bin/lean'; \
  env HOME=/tmp/tauceti-worker-home bash -lc 'test "$(command -v uv)" = /usr/local/bin/uv'; \
  env HOME=/tmp/tauceti-worker-home bash -lc 'test "$(command -v uvx)" = /usr/local/bin/uvx'; \
  rm -rf /tmp/tauceti-worker-home

# The worker. The ADD fetches main's current commit so that when main advances
# this layer's cache busts and the clone re-runs — plain `docker compose build` always gets the latest.
ADD https://api.github.com/repos/eohjelle/TauCetiWorker/commits/main /tmp/worker-head.json
RUN git clone https://github.com/eohjelle/TauCetiWorker.git /opt/tauceti

# Refresh the full Claude OAuth login before its access token expires.
COPY claude-refresh-loop /usr/local/bin/claude-refresh-loop
RUN chmod 0755 /usr/local/bin/claude-refresh-loop
WORKDIR /opt/tauceti

# Make HTTPS git operations use the token stored by GitHub CLI.
# System-level configuration remains visible after TauCeti isolates $HOME.
RUN git config --system credential.https://github.com.helper "" \
  && git config --system --add \
  credential.https://github.com.helper \
  "!gh auth git-credential"
