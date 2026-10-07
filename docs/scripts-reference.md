# Scripts reference — exactly what each script does to your PC

Before running a script on your PC, you should know what it changes. This page lists, for every script in this repository, **every change it makes**, **every internet address it contacts**, and **how to undo it**.

The same information is in each script's built-in help:

```powershell
Get-Help .\scripts\Enable-WakeOnLan.ps1 -Full
```

---

## Our rules for every script

These rules are part of the project, and the automated checks enforce some of them:

| Rule | How you can verify it |
|---|---|
| **Plain, readable code.** No obfuscation, no compiled binaries, no encoded commands. | Open any `.ps1` file in Notepad. The automated check rejects encoded commands and Base64-decoded code. |
| **Never downloads and runs code.** Software is installed only through **winget** (Microsoft's package manager) and the official Arduino/Espressif package indexes. | The automated check rejects `Invoke-Expression`, `DownloadString`, `DownloadFile`, BITS downloads and similar patterns. |
| **No telemetry.** Scripts contact only the addresses listed on this page. | "Network access" sections below. |
| **Administrator only when needed.** Scripts that need it say so and refuse to run without it. | `#Requires -RunAsAdministrator` or an explicit check at the top of the script. |
| **Secrets stay on your PC.** `config.h` is git-ignored, and the agent token is in a folder only Administrators can read. | `.gitignore`; the agent install folder's permissions. |
| **Safe to run again.** Running a script twice leaves the same result. | |
| **Everything can be undone.** | "Undo" sections below. |

### Automated analysis

GitHub runs [`tests/Invoke-ScriptAnalysis.ps1`](../tests/Invoke-ScriptAnalysis.ps1) on every pull request to `main` (before merging) and on every push to `main` (including merges):

1. **Syntax:** every script must parse in Windows PowerShell 5.1, the version included with Windows.
2. **Forbidden patterns:** no downloading and running code, no hidden code (see the table above).
3. **[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer):** Microsoft's static analyzer for PowerShell, with all its default rules except the two listed in [`PSScriptAnalyzerSettings.psd1`](../PSScriptAnalyzerSettings.psd1), each with its reason. Among others, it flags `Invoke-Expression`, passwords in plain-text parameters, empty error handling and unsafe credential handling.

Results are public in the repository's **Actions** tab. You can run the same checks yourself:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-ScriptAnalysis.ps1
```

### Make sure you run the published code

Download the repository with `git clone` instead of copying scripts from other places. Then:

```powershell
git status     # must say "nothing to commit, working tree clean": no file was modified
git log -1     # the commit ID must match the latest commit shown on GitHub
```

---

## Summary

| Script | Admin | Changes your PC | Internet access |
|---|---|---|---|
| [`Enable-WakeOnLan.ps1`](#enable-wakeonlanps1) | Yes (`-CheckOnly`: no) | Network adapter settings, Fast Startup | None |
| [`Install-RemoteAccess.ps1`](#install-remoteaccessps1) | Yes | Installs Tailscale; Remote Desktop settings and firewall rules | winget, Tailscale |
| [`Set-AutoSleep.ps1`](#set-autosleepps1) | No | Sleep timeout of the active power plan | None |
| [`Install-Agent.ps1`](#install-agentps1) | Yes | Agent folder, firewall rule, startup task | None |
| [`Uninstall-Agent.ps1`](#uninstall-agentps1) | Yes | Removes what `Install-Agent.ps1` added | None |
| [`Install-DevTools.ps1`](#install-devtoolsps1) | No | Installs Git, Arduino IDE/CLI, ESP32 package, libraries | winget, Arduino, Espressif, GitHub |
| [`New-FirmwareConfig.ps1`](#new-firmwareconfigps1) | Only to read the agent token | Writes `config.h` inside the repository | Telegram (only to detect your ID) |
| [`Install-Firmware.ps1`](#install-firmwareps1) | No | Nothing on the PC; writes the firmware to the ESP32 | None |
| [`Send-MagicPacket.ps1`](#send-magicpacketps1) | No | Nothing | None (local network broadcast) |
| [`Set-StaticIp.ps1`](#set-staticipps1) | Yes | Fixed IP address, gateway and DNS on the wired adapter | None (local network pings) |
| [`tests/Invoke-ScriptAnalysis.ps1`](#testsinvoke-scriptanalysisps1) | No | Nothing | None |
| [`agent/RemotePcWakeAgent.ps1`](#agentremotepcwakeagentps1) | Runs as SYSTEM | Runs in the background (see below) | None (only answers the ESP32) |

---

## Enable-WakeOnLan.ps1

Configures Windows so the PC can be powered on by Wake-on-LAN. [Runbook 01, Part B](01-pc-setup-bios-and-windows.md#part-b--windows)

**Changes made to this PC** (only on the wired adapter it selects; with `-CheckOnly`, nothing):

| What | Change |
|---|---|
| Adapter advanced properties, only those the driver has | `Wake on Magic Packet` → On; `Wake on pattern match` → Off; `Shutdown Wake-On-Lan` → On; `Enable PME` → On; `Energy-Efficient Ethernet`, `Advanced EEE`, `Green Ethernet` → Off |
| Adapter power management | Wake on magic packet → On; wake on pattern → Off |
| Registry: the adapter's key under `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}` | `PnPCapabilities` = 24 (unchecks "Allow the computer to turn off this device to save power") |
| Wake permission | `powercfg /deviceenablewake "<adapter>"` |
| Registry: `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` | `HiberbootEnabled` = 0 (Fast Startup off) |
| Adapter restart | The network drops for a few seconds if a setting changed |

**Reads:** network adapters, IP addresses, wake-armed devices.
**Network access:** none.

**Undo:**

```powershell
# Fast Startup back on
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' HiberbootEnabled 1
# Adapter can no longer wake the PC
powercfg /devicedisablewake "<adapter name as shown in Device Manager>"
```

Restore the adapter's settings in **Device Manager → Network adapters → your adapter → Advanced / Power Management**. Alternatively, reset every advanced setting of the adapter to its driver default with `Reset-NetAdapterAdvancedProperty -Name "Ethernet" -DisplayName *`.

---

## Install-RemoteAccess.ps1

Sets up Tailscale and Remote Desktop. [Runbook 04, Part A](04-remote-access-tailscale.md#part-a--set-up-the-pc-automatic)

**Changes made to this PC:**

| What | Change |
|---|---|
| Software | Installs **Tailscale** with winget (package `Tailscale.Tailscale`) if missing |
| Tailscale | Signs in (you approve it in your browser) and turns on *Run unattended* |
| Registry: `HKLM\System\CurrentControlSet\Control\Terminal Server` | `fDenyTSConnections` = 0 (Remote Desktop on). Skipped with `-SkipRemoteDesktop` or on Windows Home. |
| Registry: `...\Terminal Server\WinStations\RDP-Tcp` | `UserAuthentication` = 1 (Network Level Authentication required) |
| Windows Firewall | Enables the built-in **Remote Desktop** rules |
| With `-RestrictRdpToTailscale` | Those rules only accept `100.64.0.0/10`, `fd7a:115c:a1e0::/48` (Tailscale) and the local subnet |
| With `-AllowPasswordSignIn` | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device\DevicePasswordLessBuildVersion` = 0 (allows password sign-in for Microsoft accounts) |

**Reads:** Tailscale status, Windows edition, whether your account is a Microsoft account.
**Network access:** winget (Microsoft's package source, then Tailscale's official installer). Tailscale itself connects to Tailscale's coordination servers, as it does whenever you use it.

**Undo:**

- Remote Desktop: **Settings → System → Remote Desktop → Off**.
- Firewall restriction: `Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' | Set-NetFirewallRule -RemoteAddress Any`
- Password sign-in: **Settings → Accounts → Sign-in options** → turn the Windows Hello-only option back on.
- Tailscale: `tailscale logout`, then `winget uninstall --id Tailscale.Tailscale`.

---

## Set-AutoSleep.ps1

Puts the PC to sleep after N minutes of inactivity. [Runbook 04, Part F](04-remote-access-tailscale.md#part-f--save-power-when-youre-done)

**Changes made to this PC:** the *sleep after* time of the active power plan, when plugged in (`powercfg /change standby-timeout-ac <minutes>`).
**Network access:** none.
**Undo:** run it again with your previous value (`-Minutes 0` = never sleep), or **Settings → System → Power → Screen and sleep**.

---

## Set-StaticIp.ps1

Gives the PC a fixed IP address, for routers that can't reserve one. [Runbook 01, B4](01-pc-setup-bios-and-windows.md#if-your-router-cant-reserve-addresses)

**Changes made to this PC** (only on the interface that holds the LAN address: the wired adapter, or its Hyper-V `vEthernet` adapter when a Hyper-V external switch is used):

| What | Change |
|---|---|
| IPv4 addressing | DHCP off; the fixed address (the one you give, or the suggested one you confirm), with the current subnet prefix and default gateway |
| DNS servers | Set to the ones currently in use (or the gateway, if there are none) |
| If the router is unreachable afterwards | Automatically switches back to DHCP |
| With `-UseDhcp` | DHCP back on; removes the fixed address, its default route and the fixed DNS servers |

**Reads:** the interface's current address, gateway and DNS servers; the ARP table.
**Network access:** local network only. Pings candidate addresses near the top of the network (up to 40) to find a free one, or only the address you give, and pings the gateway to check the result.
**Undo:** `Set-StaticIp.ps1 -UseDhcp`, or **Settings → Network & internet → Ethernet → IP assignment → Automatic (DHCP)**.

---

## Install-Agent.ps1

Installs the PC agent. [Runbook 05](05-pc-agent.md)

**Changes made to this PC:**

| What | Change |
|---|---|
| Folder `C:\ProgramData\RemotePcWake\` | Created, with `RemotePcWakeAgent.ps1` (copied from the repository) and `config.json` (random token, port, settings). Permissions: only **SYSTEM** and **Administrators**. |
| Windows Firewall | Inbound rule **Remote PC Wake Agent** (`RemotePcWakeAgent`): TCP port 8765, only from `-Esp32Address` (default: local subnet) |
| Task Scheduler | Task **Remote PC Wake Agent**: runs the agent as SYSTEM at startup, restarts it every minute if it fails. Started immediately. |

**Network access:** only `http://localhost:8765` to test the agent.
**Undo:** `Uninstall-Agent.ps1`.

---

## Uninstall-Agent.ps1

Removes the PC agent.

**Changes made to this PC:** stops and deletes the **Remote PC Wake Agent** task, deletes the firewall rule `RemotePcWakeAgent`, and deletes `C:\ProgramData\RemotePcWake\`.
**Network access:** none.

---

## Install-DevTools.ps1

Installs the tools to build the firmware. [Runbook 02](02-development-environment.md#automatic-setup-steps-27)

**Changes made to this PC:**

| What | Change |
|---|---|
| Software (winget) | **Git** (`Git.Git`), **Arduino IDE** (`ArduinoSA.IDE.stable`, skipped with `-SkipIde`) and **Arduino CLI** (`ArduinoSA.CLI`). Only those not installed yet. |
| `%LOCALAPPDATA%\Arduino15\` | ESP32 board package (compiler and tools from Espressif) |
| `Documents\Arduino\libraries\` | Libraries `UniversalTelegramBot` and `ArduinoJson` |

**Reads:** connected USB devices, to check the ESP32's driver.
**Network access:** winget (Microsoft's package source and each tool's official download), `downloads.arduino.cc` (library and package indexes), `espressif.github.io` and `github.com` (ESP32 package).

**Undo:**

```powershell
winget uninstall --id Git.Git
winget uninstall --id ArduinoSA.IDE.stable
winget uninstall --id ArduinoSA.CLI
Remove-Item -Recurse "$env:LOCALAPPDATA\Arduino15"
Remove-Item -Recurse "$HOME\Documents\Arduino\libraries\UniversalTelegramBot", "$HOME\Documents\Arduino\libraries\ArduinoJson"
```

---

## New-FirmwareConfig.ps1

Creates or updates the firmware's `config.h`. [Runbook 03, Step 4](03-telegram-bot-flash-and-deploy.md#step-4--configure-the-firmware)

**Changes made to this PC:** writes **only** `firmware\remote-pc-wake\config.h` inside the repository. It contains your secrets (Wi-Fi password, bot token, agent token) in plain text, as the firmware needs them. It's git-ignored, so it's never committed.

**Reads:** this PC's Ethernet adapter (MAC and IP), the agent token in `C:\ProgramData\RemotePcWake\config.json`, and the current Wi-Fi name (`netsh wlan show interfaces`).

**Network access:** `api.telegram.org`, only if your Telegram ID isn't known yet. It calls `getMe` (to check the bot token) and `getUpdates` (to read the message you send to your own bot). It never sends messages. With `-Esp32StaticIp`, it also pings addresses on the local network and reads the ARP table: the given address, to warn you if it's already in use, or with `auto` up to 40 addresses near the top of the network to find a free one.

**Undo:** delete `config.h`.

---

## Install-Firmware.ps1

Builds the firmware and uploads it to the ESP32. [Runbook 03, Step 5](03-telegram-bot-flash-and-deploy.md#step-5--upload-the-firmware)

**Changes made to this PC:** none. Arduino CLI keeps temporary build files in its own cache folder. The firmware is written to the **ESP32** over USB.
**Reads:** connected USB devices, to find the ESP32's COM port.
**Network access:** none.

---

## Send-MagicPacket.ps1

Test tool: wakes a PC from another Windows PC. [Runbook 01, B5](01-pc-setup-bios-and-windows.md#b5-test-wake-on-lan-locally-before-using-the-esp32)

**Changes made to this PC:** none. Sends a Wake-on-LAN packet (UDP port 9) to your local network.
**Network access:** local network only.

---

## tests/Invoke-ScriptAnalysis.ps1

Checks all the scripts (see [Automated analysis](#automated-analysis)).

**Changes made to this PC:** none. It only reads the repository's files. Installing PSScriptAnalyzer (`Install-Module PSScriptAnalyzer -Scope CurrentUser`) adds that module to your user's PowerShell modules.
**Network access:** none (installing the module downloads it from the PowerShell Gallery).

---

## agent/RemotePcWakeAgent.ps1

The PC agent itself. It isn't run by hand: `Install-Agent.ps1` copies it to `C:\ProgramData\RemotePcWake\` and Task Scheduler runs it as SYSTEM at startup.

**What it does while running:**

| What | Detail |
|---|---|
| Listens | TCP port 8765, only answers requests carrying the token |
| Allowed actions | Report status, shut down, restart, sleep, lock the screen, cancel a scheduled shutdown. Nothing else: it can't run commands sent to it. |
| Programs it runs | `shutdown.exe` (shut down / restart / cancel) and `nvidia-smi` (GPU stats, only if installed) |
| Windows APIs | Sleep (`SetSuspendState`), lock (`WTSDisconnectSession`), shutdown privilege for itself |
| Reads | CPU, memory and disk usage, uptime, signed-in user name, the Windows Update "restart required" flag |
| Writes | `C:\ProgramData\RemotePcWake\agent.log` (requests and errors; rotated at 1 MB) |

**Network access:** none outgoing. It only answers requests from your local network (from the ESP32, if you restricted it with `-Esp32Address`).
**Undo:** `Uninstall-Agent.ps1`.
