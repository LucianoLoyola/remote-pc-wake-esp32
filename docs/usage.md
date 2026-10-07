# Daily use — Telegram, web UI and notifications

Once everything is set up (Runbooks 01–05), this is how you use it.

---

## Telegram (from anywhere)

### Buttons

Send `/menu` (or any unknown text) to get buttons for every action:

```
[ Wake ]     [ Status ]
[ Lock ]     [ Sleep ]
[ Restart ]  [ Shut down ]
```

**Shut down** and **Restart** ask for confirmation. Shut down also offers *Now*, *In 30 min* and *In 1 h*.

### Commands

| Command | What it does | Needs agent |
|---|---|---|
| `/wake` | Turns the PC on and tells you when it's ready | No |
| `/status` | On/off, plus CPU, RAM, disks, GPU, uptime, user and scheduled actions when the agent is installed | Stats only |
| `/shutdown` | Asks for confirmation, then shuts down | Yes |
| `/shutdown 45` | Shuts down in 45 minutes | Yes |
| `/restart` / `/restart 10` | Restart now / in 10 minutes | Yes |
| `/sleep` | Puts the PC to sleep (`/wake` brings it back) | Yes |
| `/lock` | Locks the PC's screen; apps keep running | Yes |
| `/cancel` | Cancels a scheduled shutdown/restart | Yes |
| `/menu` | Shows the buttons | No |

> Replies can take up to `POLL_INTERVAL_SECONDS` (15 s by default), because the ESP32 checks Telegram periodically to save power.

---

## Web UI (home network)

Open **http://remote-pc-wake.local** (or the ESP32's IP) in any browser on your home network and sign in:

| Field | Value |
|---|---|
| User | `admin` (unless you changed `WEB_USERNAME` in `config.h`) |
| Password | The one you chose when `New-FirmwareConfig.ps1` asked for the *Web UI password* (`WEB_PASSWORD` in `config.h`) |

Forgot the password? Set a new one and flash the ESP32 again:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1 -ChangeWebPassword
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1
```

It shows:

- PC status (on / off / waking up), hostname, user and uptime
- CPU, RAM and GPU usage, disk bars, warnings
- Scheduled shutdown/restart with time remaining
- Buttons: Wake, Lock, Sleep, Restart, Shut down (now or scheduled), Cancel
- ESP32 info: firmware version, uptime and Wi-Fi signal

It refreshes every 10 seconds. Every action taken from the web UI is also reported in Telegram (Web UI: ...), so you have a log of what was done.

> **Enable it** by setting `WEB_PASSWORD` in `config.h`. It stays disabled while the password is empty.
>
> `.local` names work on Windows 10+, macOS, iOS and most Linux systems. If it doesn't resolve (some Android versions), use the ESP32's IP address instead (reserve it in your router, or give it a fixed one: [Runbook 05, Step 1](05-pc-agent.md#step-1--reserve-an-ip-for-the-esp32)).

### Why is the web UI only available at home?

The ESP32 is a microcontroller, not a computer: it can't run Tailscale. There's no official Tailscale client for microcontrollers. So the web UI is only reachable from your home network.

**From anywhere**, use Telegram: the buttons give you the same actions.

**To also reach the web UI from anywhere**, you need **one always-on device at home running Tailscale as a subnet router**, for example:

- a MikroTik router (RouterOS 7 with the Tailscale container),
- a Raspberry Pi, NAS or home server,
- an OpenWrt router with the Tailscale package.

On that device, advertise a route to the ESP32's IP only:

```bash
tailscale up --advertise-routes=192.168.1.50/32   # the ESP32's IP
```

Then approve the route in the [Tailscale admin console](https://login.tailscale.com/admin/machines) (machine → **⋯** → **Edit route settings**). From any of your Tailscale devices, open `http://192.168.1.50`.

> The target PC itself can't do this job: when it's off (exactly when you need to wake it), the route disappears with it.

---

## Notifications

The ESP32 checks the PC every `MONITOR_INTERVAL_SECONDS` (30 s) and sends you a message when something happens:

| Message | When | Setting |
|---|---|---|
| ESP32 online | The ESP32 started, e.g. **power came back after an outage** | Always on |
| The PC is online (took N s) | After `/wake` | Always on |
| The PC has shut down / The PC is asleep | After `/shutdown` / `/sleep` | Always on |
| The PC restarted and is back online | After `/restart` | Always on |
| The PC was turned on, but not from the bot | Someone (or something) turned it on | `NOTIFY_UNEXPECTED_POWER_ON` |
| The PC went offline, but not from the bot | Shut down at the PC, crash, power loss, or network cable unplugged | `NOTIFY_UNEXPECTED_POWER_OFF` |
| The PC is on, but the agent is not responding | Agent stopped, or the token is wrong | Always on (with agent) |
| Disk C: is 93% full | A disk is fuller than `DiskWarningPercent` (agent config) | `NOTIFY_AGENT_WARNINGS` |
| Windows Update needs a restart | Windows is waiting to restart for updates | `NOTIFY_AGENT_WARNINGS` |
| The PC did not come online / is still on | A requested power change didn't happen in time | Always on |
| Web UI: ... | An action was taken from the web UI | Always on |

To avoid false alarms, a state change must be confirmed by two consecutive checks (four for "agent not responding"). Each disk or Update warning is sent once per power-on.

---

## Typical session

1. **`/wake`** → "Magic packet sent…" → about 1 minute later "The PC is online".
2. Turn on **Tailscale** on your laptop/phone and connect with **Remote Desktop** to the PC ([Runbook 04](04-remote-access-tailscale.md)).
3. Work.
4. Disconnect and **`/shutdown`** → *Now*, or **`/shutdown 60`** if something is still running.
5. "The PC has shut down."
