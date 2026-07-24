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

# Lean toolchain (elan/lake) + uv (runs the tauceti PEP-723 shim).
RUN curl -fsSL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y \
       && curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.elan/bin:/root/.local/bin:${PATH}" \
       PYTHONUNBUFFERED=1

# The worker (your fork). The ADD fetches main's current commit so that when main advances this layer's
# cache busts and the clone re-runs — plain `docker compose build` always gets the latest fork commit.
ADD https://api.github.com/repos/kim-em/TauCetiWorker/commits/main /tmp/worker-head.json
RUN git clone https://github.com/kim-em/TauCetiWorker.git /opt/tauceti

# Refresh the full Claude OAuth login before its access token expires.
COPY claude-refresh-loop /usr/local/bin/claude-refresh-loop
RUN chmod 0755 /usr/local/bin/claude-refresh-loop
WORKDIR /opt/tauceti