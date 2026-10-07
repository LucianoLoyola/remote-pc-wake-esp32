# Runbook 04 — Remote access with Tailscale and Remote Desktop

Waking the PC is only half the story. This runbook lets you **use** it from anywhere: see its screen, run its programs, grab its files.

**Estimated time:** 15 minutes (5 with the script).

---

## How it fits together

```
 1. /wake on Telegram  ──►  ESP32  ──►  PC powers on
 2. Tailscale on your phone/laptop  ════ encrypted tunnel ════►  PC (shown as "my-desktop")
 3. Remote Desktop  ──►  my-desktop  ──►  you see and control the PC's screen
```

[Tailscale](https://tailscale.com) builds a private network between **your own devices**. Each device gets a fixed `100.x.y.z` address and a name (e.g. `my-desktop`) that work from any internet connection: home Wi-Fi, mobile data, hotel, office.

- **No ports opened** on your router, and it works behind CGNAT.
- **Only the PC is reachable**, not the rest of your home network. The PC is a regular node, not a VPN gateway.
- **Free** for personal use (up to 100 devices).

## What you can do once connected

| Goal | Tool |
|---|---|
| Use the full desktop: apps, browser, everything | **Remote Desktop** ([Part C](#part-c--connect-from-your-devices)) |
| Copy files to/from the PC | Shared folders over Tailscale, or **Taildrop** ([Part D](#part-d--files)) |
| Use your PC's power from a weak laptop (compile, render, run heavy software) | Remote Desktop |
| Gaming / low latency / multiple monitors | [Parsec](https://parsec.app) or [Moonlight](https://moonlight-stream.org) + [Sunshine](https://app.lizardbyte.dev/Sunshine/) |
| Command line | `ssh` (with the Windows OpenSSH server) over Tailscale |
| Turn the PC off when done | `shutdown /s /t 0` from the remote session |

---

## Part A — Set up the PC (automatic)

Run the setup script on the **target PC** from an **elevated** PowerShell window (right-click Start → **Terminal (Admin)**):

```powershell
cd path\to\remote-pc-wake-esp32
powershell -ExecutionPolicy Bypass -File .\scripts\Install-RemoteAccess.ps1
```

The script:

1. Installs Tailscale with `winget` (if needed).
2. Signs you in. A link appears; open it and log in. The PC is set to **Run unattended**, so it stays reachable at the login screen after a Wake-on-LAN boot.
3. Enables **Remote Desktop** with Network Level Authentication (Pro/Enterprise/Education).
4. Warns about common pitfalls and prints the PC's **Tailscale name** and how to connect.

It's safe to run more than once.

| Option | Use it when |
|---|---|
| `-RestrictRdpToTailscale` | You want Remote Desktop to accept connections only from Tailscale and your LAN (recommended) |
| `-SkipRemoteDesktop` | Windows Home, or you'll use RustDesk/Parsec instead |
| `-AuthKey tskey-...` | Signing in without a browser, using an [auth key](https://login.tailscale.com/admin/settings/keys) |
| `-AllowPasswordSignIn` | Your Microsoft account is set to Windows Hello only, so Remote Desktop rejects your password ([A5](#a5-microsoft-account-sign-in)) |

**One manual step remains:** [disable key expiry](#a3-disable-key-expiry-required) (A3). The script tells you if it's still needed.

---

## Part A — Set up the PC (manual)

Skip this part if the script ran successfully, except for **A3**.

### A1. Install Tailscale and sign in

1. Install from <https://tailscale.com/download/windows>, or:
   ```powershell
   winget install --id Tailscale.Tailscale -e
   ```
2. Tailscale tray icon → **Log in** and sign in (Google, Microsoft, GitHub, Apple…).

### A2. Enable "Run unattended"

After a Wake-on-LAN boot, the PC sits at the login screen with nobody signed in. Without this setting, Tailscale stays disconnected in that state.

- Tailscale tray icon → **Preferences** → **Run unattended** ✓

### A3. Disable key expiry (required)

Tailscale keys expire after 180 days by default. When that happens, you have to sign in again **physically at the PC**, which defeats the purpose.

1. Open <https://login.tailscale.com/admin/machines>.
2. Find your PC → **⋯** → **Disable key expiry**.

### A4. Enable Remote Desktop

Windows **Pro, Enterprise or Education** only. On Home, see [Part E](#part-e--windows-home-and-alternatives).

1. **Settings → System → Remote Desktop** → **On** → **Confirm**.
2. Keep **Require devices to use Network Level Authentication** enabled.

Administrators can connect by default. To allow a standard (non-admin) account, add it under **Remote Desktop users**.

### A5. Microsoft account sign-in

If you sign in to Windows with a **Microsoft account**, Remote Desktop needs your **account email and password**, not your PIN.

If your account is passwordless (Windows Hello only), Remote Desktop rejects your credentials.

**Automatic:** run `Install-RemoteAccess.ps1 -AllowPasswordSignIn`, then sign out and sign in once **with your password**.

**Manual:**

1. **Settings → Accounts → Sign-in options** → turn **off** "For improved security, only allow Windows Hello sign-in for Microsoft accounts on this device".
2. Sign out and sign in once **with your password**.

---

## Part B — Set up your other devices

Install Tailscale on every device you'll connect **from**, and sign in with the **same account**:

| Device | Get it |
|---|---|
| Android | [Google Play](https://play.google.com/store/apps/details?id=com.tailscale.ipn) |
| iPhone / iPad | [App Store](https://apps.apple.com/app/tailscale/id1470499037) |
| Windows / macOS / Linux | <https://tailscale.com/download> |

Turn Tailscale **on** before connecting to the PC. You can leave it on all the time; it only routes traffic for your Tailscale devices, and the rest of your internet traffic is unaffected.

Check that your PC appears in the device list in the Tailscale app.

---

## Part C — Connect from your devices

### Remote Desktop client

| Device | App |
|---|---|
| Windows | **Windows App** from the Microsoft Store, or built-in `mstsc` |
| macOS / iPhone / iPad / Android | **Windows App** (formerly *Microsoft Remote Desktop*) |

### Connect

1. `/wake` in Telegram and wait for "The PC is online".
2. Make sure Tailscale is **on** in your device.
3. In the Remote Desktop app, add a PC with:
   - **PC name:** the Tailscale name (e.g. `my-desktop`) or its `100.x.y.z` IP
   - **User:** your Microsoft account email, or your local Windows username
4. Connect and enter your password.

From Windows you can also just run:

```powershell
mstsc /v:my-desktop
```

### Tips

- **First test from outside home:** turn off Wi-Fi on your phone (use mobile data) and connect. If that works, it works from anywhere.
- **Phone:** switch the app to *mouse pointer* mode for precise clicks. Pinch to zoom.
- **Slow connection:** in the connection settings, lower the resolution and color depth, and disable the wallpaper.
- Your PC's screen locks while you're connected remotely, so nobody at home can see what you're doing.
- **When finished:** *disconnect* to leave your programs running, *sign out* to close them, or shut the PC down with `shutdown /s /t 0`.

---

## Part D — Files

**Option 1 — Shared folders (Windows to Windows).** Share a folder on the PC (*Properties → Sharing*). Then, from another Windows device connected to Tailscale, open File Explorer and go to:

```
\\my-desktop\SharedFolderName
```

**Option 2 — Taildrop (any device).** Send files between your devices from the system share menu (phone) or by right-clicking the file → *Send with Tailscale* (Windows). On the command line:

```powershell
tailscale file cp .\report.pdf my-laptop:
```

**Option 3 — Remote Desktop clipboard.** Copy and paste files directly into the Remote Desktop window (Windows and macOS clients).

---

## Part E — Windows Home and alternatives

Windows Home can't **host** Remote Desktop sessions. Use one of these on the PC instead. They all work over Tailscale:

| Tool | Notes |
|---|---|
| [RustDesk](https://rustdesk.com) | Open source. Enable **direct IP access** and connect to the Tailscale IP. Install it as a **service** so it works at the login screen. |
| [Parsec](https://parsec.app) | Very low latency; great for gaming and multiple monitors. Runs as a service when installed "for all users". |
| [Chrome Remote Desktop](https://remotedesktop.google.com) | Simplest. Works at the login screen once remote access is set up. |

Whatever you choose, make sure it **starts with Windows before anyone logs in**. Otherwise it won't be reachable after a Wake-on-LAN boot.

---

## Part F — Save power when you're done

### Sleep automatically

Let the PC go to sleep by itself after a period of inactivity; `/wake` brings it back.

**Automatic** (elevated PowerShell, e.g. 60 minutes; `-Minutes 0` turns it off):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Set-AutoSleep.ps1 -Minutes 60
```

**Manual:** Settings → System → Power → **Screen and sleep** → *When plugged in, put my device to sleep after* → choose the time.

### Shut down when finished

- From Telegram: `/shutdown`, or `/shutdown 30` to shut down in 30 minutes (needs the [PC agent](05-pc-agent.md)).
- From the remote session: Start → Power → Shut down, or `shutdown /s /t 0`.

---

## Security notes

- Remote Desktop is only reachable through Tailscale. **Never** forward port 3389 on your router.
- Use a **strong Windows password**, because it's the second lock after Tailscale.
- Turn on two-factor authentication for the account you use to sign in to Tailscale (Google, Microsoft, GitHub…). Whoever controls that account can join your private network.
- Review your devices from time to time at <https://login.tailscale.com/admin/machines> and remove any you don't recognize.
- Optional: run the script with `-RestrictRdpToTailscale` so Remote Desktop only answers on Tailscale and your LAN.

---

## Verification checklist

- [ ] Tailscale installed on the PC, signed in, **Run unattended** on
- [ ] **Key expiry disabled** for the PC in the admin console
- [ ] Remote Desktop (or alternative) enabled
- [ ] Tailscale installed on your phone/laptop with the same account
- [ ] Remote Desktop works **from mobile data** (outside home)
- [ ] Full cycle works: PC off → `/wake` → "online" → connect → shut down

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| PC doesn't appear online in Tailscale after a WoL boot | "Run unattended" is off (A2), or the key expired (A3) |
| "The credentials did not work" | See A5. Use your Microsoft account email, not your PIN. |
| "Remote Desktop can't find the computer" | Tailscale is off on your device, or you're using the wrong name. Try the `100.x.y.z` IP. |
| Connects at home but not from outside | Tailscale is off on your device: at home you were connecting through the LAN directly. |
| Very slow / laggy | Lower the resolution in the Remote Desktop app. Run `tailscale status` on the PC: if you see `relay`, the connection goes through a Tailscale relay server (slower but works). For gaming, use Parsec. |
| Script fails with "winget is not available" | Install **App Installer** from the Microsoft Store, or install Tailscale manually and run the script again. |
| Script fails with "cannot be loaded because running scripts is disabled" | Run it with `powershell -ExecutionPolicy Bypass -File ...` as shown above. |
