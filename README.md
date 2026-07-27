# tauceti in Docker

Run the tauceti loop in a container, using **both Codex and Claude**, on your
own subscriptions — no API keys. The container _is_ the sandbox, so it runs in host mode (no
bubble). Agent creds are stored in **files** on Linux, so the loop refreshes its tokens in place
and keeps running unattended; the creds persist across restarts via named volumes.

Runs on any Docker host. It needs disk (image ~2–3 G, a Lean toolchain in the `elan` volume,
and Mathlib/TauCeti build state in the `checkouts` volume) and RAM (Lean builds want ≥8 G).

## 1. Build

From this repo's directory:

```bash
docker compose build
```

## 2. Authenticate (one-time; creds persist in the volumes)

Start a shell in the container — this creates its volumes — and log in to each service:

```bash
docker compose run --rm tauceti bash
# then, inside the container:
codex login --device-auth   # prints a URL + code; open the URL in a browser and enter the code
gh auth login               # choose a web-browser login and paste the one-time code
claude                      # follow the login prompt (opens/prints a URL to authorize)
exit
```

Note: The claude login has a known bug where copying the url can lead to random line breaks in the url, leading to an `Authorization failed` error. To get around this, paste the url into a text document and remove the line breaks before opening it.

To verify:

```bash
docker compose run --rm tauceti ./tauceti doctor   # gh / git / uv / jq / lake / claude+codex creds all OK
```

## Lean toolchain layout

TauCetiWorker gives each worker an isolated `HOME` for agent credentials and mutable agent state.
Lean is deliberately shared instead: Elan stores its settings and downloaded toolchains in the
persistent `elan` volume at `/opt/elan`, while its `elan`, `lake`, and `lean` proxy executables live
in `/usr/local/bin`. The proxies therefore remain visible even after `HOME` changes or an agent
starts a login shell.

To verify the tools are independent of `HOME`:

```bash
docker compose run --rm tauceti \
  env HOME=/tmp/isolated-home bash -lc '
    echo "ELAN_HOME=$ELAN_HOME"
    command -v elan
    command -v lake
    command -v lean
    command -v uv
    command -v uvx
  '
```

The expected executable paths are under `/usr/local/bin`, and `ELAN_HOME` should be `/opt/elan`.

## 3. Run

```bash
docker compose up -d            # starts the loop, restarts on crash/reboot
docker compose logs -f          # live: scheduler + agent narration/commands (Claude) + Codex output
```

Durable per-round logs are in the `logs` volume; full Claude transcripts in the `claude` volume
(`/root/.claude/projects`).

## Stop / reset

```bash
docker compose down                 # stop (keeps credentials, toolchains, and build state)
docker compose down -v              # stop AND delete volumes (re-auth + toolchain/cache downloads next time)
```
