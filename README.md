# tauceti in Docker

Run the tauceti loop in a container, using **both Codex and Claude** (`--agent auto`), on your
own subscriptions — no API keys. The container _is_ the sandbox, so it runs in host mode (no
bubble). Agent creds are stored in **files** on Linux, so the loop refreshes its tokens in place
and keeps running unattended; the creds persist across restarts via named volumes.

Runs on any Docker host. It needs disk (image ~2–3 G + Mathlib cache ~8 G in the `checkouts`
volume) and RAM (Lean builds want ≥8 G).

## 1. Build

From this repo's directory:

```bash
docker compose build            # builds for the host architecture (arm64 or amd64)
# cross-build if targeting a different arch:
#   docker buildx build --platform linux/amd64 -t tauceti-worker .
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

## 3. Run

```bash
docker compose up -d            # starts the loop, restarts on crash/reboot
docker compose logs -f          # live: scheduler + agent narration/commands (Claude) + Codex output
```

Durable per-round logs are in the `logs` volume; full Claude transcripts in the `claude` volume
(`/root/.claude/projects`).

## Stop / reset

```bash
docker compose down                 # stop (keeps volumes = creds + build cache)
docker compose down -v              # stop AND delete volumes (re-auth + cold rebuild next time)
```
