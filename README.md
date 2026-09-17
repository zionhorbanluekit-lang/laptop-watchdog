# Laptop watchdog

Zero-budget healthchecks.io: the laptop edits one Discord message every minute;
a GitHub Actions cron alerts when that message stops changing.

## Setup
1. Discord → channel settings → Integrations → Webhooks → copy URL.
2. `copy config.example.json config.json`, fill `webhook` and `botProcess` (process name without `.exe`, e.g. `python`, `node`).
3. `powershell -ExecutionPolicy Bypass -File heartbeat.ps1 -Install` — posts the status message, prints its id, drops a shortcut in the Startup folder (no admin needed), and starts the loop.
4. Pin that status message in Discord — that's your status page.
5. Push this folder to a GitHub repo (private is fine). Repo → Settings → Secrets → Actions: add `DISCORD_WEBHOOK` and `STATUS_MSG_IDS` (comma-separated if monitoring more than one laptop, see below).
6. Stop the laptop from sleeping: `powercfg /change standby-timeout-ac 0` and set lid-close action to "Do nothing".

## Monitoring more than one laptop
Each laptop gets its own copy of `heartbeat.ps1` + its own `config.json` (own `statusMessageId`),
but they can all post to the **same** Discord webhook — each shows up as a separate message
in the channel, distinguished by `$env:COMPUTERNAME` in the status line.

1. Copy `heartbeat.ps1` to the other laptop (any folder).
2. On that laptop, create `config.json` there with the **same `webhook`**, an **empty
   `statusMessageId`**, and that laptop's own `botProcess`.
3. Run `-Install` there — it posts a *new* status message and prints its id.
4. Add that id to the `STATUS_MSG_IDS` GitHub secret, comma-separated: `id1,id2`.

## What alerts, and how fast
| event | detected by | delay |
|---|---|---|
| bot process died / back | laptop | ≤ 1 min |
| charger unplugged / low battery / power back | laptop | ≤ 1 min |
| laptop dead, no internet, asleep | GitHub cron | 15–30 min (cron is best-effort) |
| laptop back online | laptop | ≤ 1 min, says how long it was down |

## Notes
- `heartbeat.ps1 -Once` = one tick, prints the status line. Use it to test.
- GitHub disables cron workflows after 60 days with no commits — push anything to re-enable.
- Want an .exe? `Install-Module ps2exe; Invoke-ps2exe heartbeat.ps1 heartbeat.exe` (then point the task at it).
