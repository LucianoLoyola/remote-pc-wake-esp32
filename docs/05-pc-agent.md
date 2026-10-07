# Runbook 05 — PC agent (shutdown, restart, sleep, lock, stats)

The ESP32 can **turn the PC on** by itself. To also **turn it off**, restart it, put it to sleep, lock it, or read its stats, the PC needs a small helper: the **agent**.

**Estimated time:** 5 minutes.

---

## What the agent does

The agent is a small PowerShell service that runs in the background on the target PC and listens for requests from the ESP32 on your local network.

| Feature | Telegram | Web UI |
|---|---|---|
| Shut down (now or scheduled) | `/shutdown`, `/shutdown 30` | Shut down |
| Restart (now or scheduled) | `/restart`, `/restart 10` | Restart |
| Sleep | `/sleep` | Sleep |
| Lock the screen | `/lock` | Lock |
| Cancel a scheduled shutdown/restart | `/cancel` | Cancel |
| Stats: CPU, RAM, disks, GPU (NVIDIA), uptime, signed-in user | `/status` | Status panel |
| Warnings: disk almost full, Windows Update restart pending | Automatic alerts | Status panel |

Everything else (wake, power-on/offline alerts) works **without** the agent.

```
 ESP32 ── HTTP + token (LAN only) ──► agent on the PC (port 8765) ──► shutdown / sleep / lock / stats
```

### How it runs

- A **scheduled task** starts it as `SYSTEM` when Windows boots, before anyone signs in. It's available right after a Wake-on-LAN boot.
- It only answers requests that carry the **shared token**, a random 48-character secret generated at install time.
- **Windows Firewall** only lets the ESP32's IP address (or your local network) reach it.
- The agent is **not reachable from the internet**. Only the ESP32 talks to it.
- No extra software needed: it uses PowerShell, which ships with Windows.

---

## Step 1 — Reserve an IP for the ESP32

So the firewall can allow **only** the ESP32:

1. Find the ESP32's IP: it's printed in the Serial Monitor at boot (`Connected. IP: ...`), or listed in your router's connected-devices page as `remote-pc-wake`. With the web UI enabled, `ping remote-pc-wake.local` also shows it.
2. In your router, create a **DHCP reservation** for it, like you did for the PC in [Runbook 01, B4](01-pc-setup-bios-and-windows.md#b4-reserve-a-fixed-ip-for-the-pc-in-your-router).

**If your router can't reserve addresses**, give the ESP32 a fixed address in its configuration instead. Choose one outside the range the router hands out (e.g. `192.168.1.210`) and different from the PC's.

- **Automatic**, on the target PC (it takes the gateway and subnet from the PC's network settings):
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1 -Esp32StaticIp 192.168.1.210
  powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1
  ```
  To go back to automatic addressing: `New-FirmwareConfig.ps1 -Esp32UseDhcp`, then flash again.
- **Manual:** in `config.h`, set `ESP32_STATIC_IP`, `NETWORK_GATEWAY` (your router) and `NETWORK_SUBNET`, then flash again.

> You can skip this and allow your whole local network instead (the default), but restricting it to the ESP32 is safer.
>
> **Don't have the ESP32's IP yet?** Install the agent without `-Esp32Address` now. Once the ESP32 is online and its IP is reserved, run the installer again with `-Esp32Address`. It keeps the same token, so you don't need to re-flash the firmware.

## Step 2 — Install the agent

### Automatic

On the **target PC**, open an **elevated** PowerShell window (right-click Start → **Terminal (Admin)**), go to the repository folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Agent.ps1 -Esp32Address 192.168.1.50
```

Replace `192.168.1.50` with the ESP32's IP from Step 1, or leave out `-Esp32Address` to allow any device on your local network.

The installer:

1. Copies the agent to `C:\ProgramData\RemotePcWake\`, readable only by Administrators and SYSTEM.
2. Generates the token and saves it in `config.json` there.
3. Adds the firewall rule **Remote PC Wake Agent**.
4. Registers and starts the scheduled task **Remote PC Wake Agent**.
5. Tests the agent and prints two lines for the firmware:

```
    #define AGENT_TOKEN "3f9c...e1a7"
    #define AGENT_PORT  8765
```

### Manual

In an elevated PowerShell window, from the repository folder. Replace `LocalSubnet` with the ESP32's IP to restrict access to it.

1. Copy the agent and create its configuration with a random token:
   ```powershell
   $dir = "$env:ProgramData\RemotePcWake"
   New-Item -ItemType Directory -Force $dir | Out-Null
   Copy-Item .\agent\RemotePcWakeAgent.ps1 $dir
   $bytes = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
   $token = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
   @{ Token = $token; Port = 8765; ListenAddress = '+'; DiskWarningPercent = 90 } | ConvertTo-Json | Set-Content "$dir\config.json"
   $token   # write it down for config.h
   ```
2. Restrict the folder to Administrators and SYSTEM (it contains the token):
   ```powershell
   icacls $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
   ```
3. Allow the ESP32 through the firewall:
   ```powershell
   New-NetFirewallRule -Name RemotePcWakeAgent -DisplayName 'Remote PC Wake Agent' -Direction Inbound -Protocol TCP -LocalPort 8765 -RemoteAddress LocalSubnet -Action Allow -Profile Any
   ```
4. Run the agent at startup as SYSTEM: open **Task Scheduler** → **Create Task**:
   - **General:** name `Remote PC Wake Agent`; **Change User or Group** → `SYSTEM`; check **Run with highest privileges**.
   - **Triggers:** New → **At startup**.
   - **Actions:** New → Program `powershell.exe`, arguments `-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\RemotePcWake\RemotePcWakeAgent.ps1"`.
   - **Settings:** uncheck **Stop the task if it runs longer than**; check **If the task fails, restart every 1 minute**.
   - Right-click the task → **Run**.
5. Test it with the commands in [API reference](#api-reference).

## Step 3 — Update the firmware

**Automatic** (elevated PowerShell, on the target PC): `New-FirmwareConfig.ps1` reads the token from the installed agent and updates `config.h`; then upload:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1
```

**Manual:**

1. Paste the two `#define` lines into `firmware/remote-pc-wake/config.h`, replacing the existing `AGENT_TOKEN` / `AGENT_PORT` lines.
2. Upload the firmware again ([Runbook 03, Step 5](03-telegram-bot-flash-and-deploy.md#step-5--upload-the-firmware)).

## Step 4 — Test it

In Telegram, with the PC on:

1. `/status` should show CPU, RAM, disks and uptime.
2. `/lock` locks the PC's screen.
3. `/shutdown 5`, then `/cancel`. You should see a Windows notification about the scheduled shutdown, and then that it was cancelled.

---

## Installer options

| Option | Default | Purpose |
|---|---|---|
| `-Esp32Address <ip>` | `LocalSubnet` | Only this address may reach the agent |
| `-Port <port>` | `8765` | TCP port the agent listens on (must match `AGENT_PORT`) |
| `-NewToken` | off | Generate a new token (e.g. if it leaked). Update `config.h` and re-flash afterwards. |

Running the installer again **updates** the agent and keeps the existing token.

## Configuration file

`C:\ProgramData\RemotePcWake\config.json`:

| Key | Default | Meaning |
|---|---|---|
| `Token` | random | Shared secret; must match `AGENT_TOKEN` |
| `Port` | `8765` | Listening port |
| `ListenAddress` | `+` | `+` = all network interfaces |
| `DiskWarningPercent` | `90` | Warn when a disk is fuller than this |

After editing it, restart the agent:

```powershell
Stop-ScheduledTask -TaskName 'Remote PC Wake Agent'; Start-ScheduledTask -TaskName 'Remote PC Wake Agent'
```

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-Agent.ps1
```

This removes the scheduled task, the firewall rule and `C:\ProgramData\RemotePcWake\`.

---

## Good to know

- **Shutdown and restart force apps to close**, so unsaved work is lost. That's on purpose: with nobody at the PC, a "Save changes?" dialog would block the shutdown forever. The bot and the web UI ask for confirmation first.
- **"Now" means about 5 seconds**, so the agent has time to answer before Windows goes down.
- A scheduled shutdown shows a Windows notification on the PC. Anyone at the PC can cancel it with `shutdown /a`.
- **Lock** shows the lock screen. Your apps keep running.
- **GPU stats** are shown for NVIDIA cards (through `nvidia-smi`, installed with the driver). Other GPUs are simply not listed.
- **CPU temperature** isn't available: Windows doesn't expose it reliably without extra drivers.

## Security notes

- Traffic between the ESP32 and the agent is plain HTTP on your local network. The token keeps other devices out, but someone already **inside** your network who can capture traffic could read it. On a typical home network this is an acceptable trade-off. Restrict the firewall rule to the ESP32's IP (`-Esp32Address`).
- The agent can only do what its API allows (status, shutdown, restart, sleep, lock, cancel). It can't run arbitrary commands.
- The token is stored in `C:\ProgramData\RemotePcWake\config.json` (Administrators and SYSTEM only) and in `config.h` (git-ignored). Never commit it.
- If the token leaks: run the installer with `-NewToken`, update `config.h`, and re-flash.

---

## API reference

For contributors and integrations. Every request needs the header `X-Agent-Token: <token>`.

| Method | Path | Response |
|---|---|---|
| `GET` | `/api/status` | Status JSON (below) |
| `POST` | `/api/shutdown?delay=<seconds>` | `{"ok":true,"message":"Shutting down in 30 min.","uptimeSeconds":8040}` |
| `POST` | `/api/restart?delay=<seconds>` | Same as shutdown |
| `POST` | `/api/sleep` | `{"ok":true,"message":"Going to sleep."}` |
| `POST` | `/api/lock` | `{"ok":true,"message":"Screen locked."}` |
| `POST` | `/api/cancel` | `{"ok":true,"message":"Scheduled shutdown/restart cancelled."}` |

`delay` is optional (0–86400 s). Errors: `401` wrong/missing token, `400` invalid delay, `404` unknown endpoint, `500` action failed.

Status example:

```json
{
  "agentVersion": "1.0.0",
  "hostname": "DESKTOP-PC",
  "user": "DESKTOP-PC\\alex",
  "uptimeSeconds": 8040,
  "cpuPercent": 12,
  "memory": { "usedPercent": 29, "totalGB": 31.1 },
  "disks": [ { "drive": "C:", "usedPercent": 84, "freeGB": 152.1 } ],
  "gpu": { "name": "NVIDIA GeForce RTX 3070", "temperatureC": 46, "utilizationPercent": 3 },
  "pendingAction": { "action": "shutdown", "secondsRemaining": 1740 },
  "warnings": [ "Disk D: is 93% full" ]
}
```

Try it from the PC itself:

```powershell
$token = (Get-Content C:\ProgramData\RemotePcWake\config.json | ConvertFrom-Json).Token
Invoke-RestMethod http://localhost:8765/api/status -Headers @{ 'X-Agent-Token' = $token }
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Bot says "agent is not responding (no response)" | Check that the task is running: Task Scheduler → **Remote PC Wake Agent**, or `Get-ScheduledTask 'Remote PC Wake Agent'`. Read `C:\ProgramData\RemotePcWake\agent.log`. |
| "agent is not responding (wrong token)" | `AGENT_TOKEN` in `config.h` doesn't match `config.json`. Run the installer again (it prints the current token), update `config.h`, re-flash. |
| Works from the PC (`localhost`) but not from the ESP32 | Firewall: the ESP32's IP changed and doesn't match `-Esp32Address`. Reserve its IP and run the installer again. |
| `/lock` says "Could not lock the session" | Nobody is signed in at the PC's screen, so there's nothing to lock. |
| `/sleep` does nothing | Sleep may be disabled by the hardware or a policy. Check with `powercfg /a`. |
| Installer fails on "Testing the agent" | Another program may be using the port. Use `-Port 8766` and set `AGENT_PORT 8766` in `config.h`. |
