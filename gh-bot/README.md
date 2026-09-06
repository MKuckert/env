# gh-bot — overcommit-bot runbook

Periodic research bot for `MKuckert/env`: reads open issues, generates a
research comment with the local LLM (omlx), posts it as `overcommit-bot [bot]`
via a GitHub App installation token. Runs **locally in the sandbox** — that is
the point, so it can reach omlx.

## Layout

| File | Purpose |
|---|---|
| `auth.mjs` | App JWT (RS256, 540 s) → installation token; in-memory cache; one re-mint on 401 |
| `github.mjs` | Thin REST helpers (list issues, comments, post) |
| `llm.mjs` | omlx client (`/v1/chat/completions`), prompt builder |
| `bot.mjs` | One round: skip-check → LLM → post. `DRY_RUN=1` prints instead of posting |
| `run.sh` | **The cron target.** Loads `.env`, checks credentials, flock guard, runs one round |
| `verify-auth.mjs` | Live end-to-end auth check (app metadata, token mint, issue read) |
| `*.test.mjs` | Unit tests — `node --test` in this directory |

## Credentials (all gitignored)

- `.env` at repo root: `GH_APP_ID`, `GH_INSTALLATION_ID`, `OMLX_BASE_URL`, `OMLX_SETTINGS_FILE`
- `gh-bot/key.pem`: app private key (chmod 600)
- omlx API key: read from `omlx/settings.json` (`auth.api_key`) — no copy kept

## Scheduling (cron)

The cron target is `gh-bot/run.sh` — self-contained: sets PATH, cd's to the
repo root, loads `.env`, refuses missing credentials with a clear message, and
skips the tick (exit 0) if a previous round is still holding `~/.local/state/overcommit-bot/round.lock`.

Hourly, with a persistent log:

```cron
0 * * * * /workspace/env-gh-app/gh-bot/run.sh >> /home/node/.local/state/overcommit-bot/cron.log 2>&1
```

The bot exits non-zero if any issue in the round failed — cron's log captures it.

## Operations

```bash
cd /workspace/env-gh-app/gh-bot
node --test            # unit tests
../gh-bot/run.sh       # one real round (posts)
DRY_RUN=1 ../gh-bot/run.sh   # one dry round (prints, no posts)
node verify-auth.mjs   # live auth-chain check, no side effects
```

- **Logs:** `~/.local/state/overcommit-bot/cron.log` (cron) — round summary lines start with `[overcommit-bot]`.
- **Skip logic:** an issue is skipped when its *last* comment's author login ends with `[bot]` (any bot). The posted marker `🤖 **[overcommit-bot]**` is a human-readable fallback, not the skip mechanism.
- **Disable:** remove the cron line. Nothing else to stop (no daemon).
- **Key regeneration:** GitHub App settings → Private keys → Generate; replace `gh-bot/key.pem` (chmod 600). Old key stays valid until deleted.
- **Rate limits:** installation tokens get 5000 req/h; one round is ~2 calls per issue.

## Failure policy (fail loud, never fake)

- Missing credentials → non-zero exit, message names the missing item.
- omlx unreachable / non-2xx → issue counted as failed, round exits non-zero; **no** placeholder comment is ever posted.
- GitHub 401 → one re-mint + retry; second 401 aborts the round.
- One issue failing never stops the others, but the round still exits non-zero.
