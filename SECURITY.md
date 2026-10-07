# Security policy

This project can turn a PC on and off and gives remote access to it, so security problems matter. Thanks for reporting them responsibly.

## Supported versions

Only the **latest release** receives security fixes. Please update before reporting.

## Reporting a vulnerability

**Don't open a public issue.** Report it privately through GitHub:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability** ([direct link](https://github.com/LucianoLoyola/remote-pc-wake-esp32/security/advisories/new)).
3. Describe the problem, how to reproduce it, and its impact.

What to expect:

- This is a volunteer project. The maintainer aims to acknowledge reports within **7 days**.
- You'll be kept informed while the fix is prepared.
- Once a fix is released, the advisory is published and, if you want, you're credited for the report.

## Scope

**In scope:**

- ESP32 firmware: Telegram command handling and authorization, web UI, communication with the PC agent
- PC agent: authentication, the actions it allows, the network exposure of its port
- Setup scripts: anything that changes the system in ways that aren't documented in the [scripts reference](docs/scripts-reference.md), weakens security settings, or exposes secrets
- Documentation that leads users into an insecure setup

**Out of scope** (report these to their own projects):

- Telegram, Tailscale, Windows, Remote Desktop and the Arduino/Espressif toolchain themselves
- Problems that require someone who already controls the PC, the user's Telegram account or the bot token

## Security model

Knowing the design helps assess a report:

| Component | Protection |
|---|---|
| Telegram bot | Only commands from the configured Telegram user ID (`ALLOWED_CHAT_ID`) are accepted. The ESP32 verifies Telegram's TLS certificate and discards messages sent while it was offline. |
| PC agent | Requires a random 48-character token. The Windows Firewall rule only admits the ESP32's address (or the local subnet). It can only report status, shut down, restart, sleep, lock and cancel; it can't run arbitrary commands. |
| Web UI | Local network only, HTTP Basic authentication, and a custom header on actions that blocks cross-site requests. Every action is reported in Telegram. |
| Remote access | Through Tailscale only; Remote Desktop and the agent are never exposed to the internet. |
| Secrets | `config.h` is git-ignored. The agent token is stored in a folder only SYSTEM and Administrators can read. |

**Known limitations** (by design, not vulnerabilities):

- Traffic between the ESP32 and the PC agent, and the web UI, use plain HTTP on the local network. Someone already inside your network who can capture traffic could read the agent token or the web UI password.
- The firmware stores its secrets (Wi-Fi password, bot token, agent token) on the ESP32. Anyone with physical access to the board can read them.

## If a secret leaks

| Leaked | What to do |
|---|---|
| Bot token | Send `/revoke` to @BotFather, then `New-FirmwareConfig.ps1 -BotToken "<new token>"` and flash the ESP32 again. |
| Agent token | `Install-Agent.ps1 -NewToken`, then `New-FirmwareConfig.ps1` (as Administrator) and flash the ESP32 again. |
| Web UI password | `New-FirmwareConfig.ps1 -ChangeWebPassword` and flash the ESP32 again. |
| Wi-Fi password | Change it on the router, then `New-FirmwareConfig.ps1 -ChangeWifiPassword` and flash the ESP32 again. |
