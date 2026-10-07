# Contributing to remote-pc-wake-esp32

Thanks for helping! Bug reports, hardware compatibility reports, documentation fixes and code are all welcome.

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). To report a security problem, **don't open a public issue**: follow the [Security policy](SECURITY.md).

---

## Ways to contribute

| You want to... | Do this |
|---|---|
| Report a bug | Open an issue with the **Bug report** form. Include your hardware and the serial monitor output. |
| Say it works (or doesn't) on your hardware | Open an issue with the **Hardware report** form. These reports are very valuable: they tell others which boards, motherboards and routers work. |
| Suggest a feature | Open an issue with the **Feature request** form. Check the [roadmap](README.md#roadmap--pending) first. |
| Fix or add something | Open a pull request (see below). For bigger changes, open an issue first so we can agree on the approach. |

---

## Development setup

You need a Windows PC. Everything else is installed by the scripts:

```powershell
git clone https://github.com/LucianoLoyola/remote-pc-wake-esp32.git
cd remote-pc-wake-esp32
powershell -ExecutionPolicy Bypass -File .\scripts\Install-DevTools.ps1     # Arduino CLI/IDE, ESP32 package, libraries
Install-Module PSScriptAnalyzer -Scope CurrentUser                             # for the script checks
```

Useful commands:

```powershell
# Check every PowerShell script (the same checks GitHub runs on pull requests)
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-ScriptAnalysis.ps1

# Build the firmware without uploading (needs a config.h; see Runbook 03)
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -CompileOnly
```

Never commit `firmware/remote-pc-wake/config.h`: it contains your Wi-Fi password and tokens. It's git-ignored; keep it that way.

---

## Project rules

These rules keep the project safe to run on other people's PCs and easy to follow.

### PowerShell scripts

- **One script per Windows configuration**, in `scripts/`, with shared helpers in `scripts/lib/Common.ps1`.
- **Windows PowerShell 5.1 compatible**: it's the version every Windows PC has. No `??`, `?.`, ternary operators or other PowerShell 7-only syntax.
- **Never download and run code**, and never hide what a script does: no `Invoke-Expression`, encoded commands or Base64-decoded code. The automated checks reject them.
- **Install software only through winget** or the official Arduino/Espressif indexes.
- **Ask for Administrator only when needed** (`#Requires -RunAsAdministrator` or `Assert-Admin`).
- **Safe to run again**: running a script twice must leave the same result.
- **Passwords as `SecureString`**, asked for with `Read-Host -AsSecureString`, never as plain command-line arguments.
- **Document every change it makes.** Every script that changes the PC must have:
  1. a `.NOTES` section in its help listing the changes, the network access and how to undo them;
  2. an entry in [docs/scripts-reference.md](docs/scripts-reference.md) with the same information;
  3. an **Automatic** and a **Manual** option in the matching runbook, so people can do it by hand.
- `tests/Invoke-ScriptAnalysis.ps1` must pass.

### Firmware

- Keep it **low power**: the ESP32 runs 24/7. Don't shorten the idle delay or the polling intervals without a good reason.
- **New `config.h` settings** need a default in `remote-pc-wake.ino` (`#ifndef ... #define ... #endif`), so older `config.h` files keep compiling, and an entry in `config.example.h` and in [Runbook 03](docs/03-telegram-bot-flash-and-deploy.md).
- **Telegram commands** are only accepted from `ALLOWED_CHAT_ID`. Keep it that way.
- Test on real hardware before opening the pull request, and say which board you used.

### Documentation

- **English**, plain and direct.
- **No emojis** in the documentation.
- Keep the [onboarding guide](docs/00-getting-started.md) in sync with the runbooks: it's the entry point for new users.
- Relative links must work (they're checked when we review the pull request).

### Commits and pull requests

- One topic per pull request.
- Commit messages: a short summary line in the imperative ("Add X", "Fix Y"), then a blank line and a body explaining **why**, when it isn't obvious.
- Fill in the pull request template: what changed, how you tested it, and on which hardware.
- The **Analyze PowerShell scripts** check must pass before merging.

---

## Versioning and releases

The project uses [semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **The release version and the firmware version are the same number.** The firmware reports it in the "ESP32 online (vX.Y.Z)" message and in the web UI.
- The PC agent has its own API version (`agentVersion`), which only changes when its API changes.

To publish a release (maintainers):

1. Set `FIRMWARE_VERSION` in `firmware/remote-pc-wake/remote-pc-wake.ino` to the new version, in a pull request.
2. After merging, create the tag `vX.Y.Z` on `main` and publish the GitHub release with its notes.
