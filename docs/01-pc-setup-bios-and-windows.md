# Runbook 01 — PC setup (BIOS/UEFI and Windows)

This runbook prepares the **target PC** (the one you want to turn on and control remotely) so that:

1. It can be powered on by a Wake-on-LAN (WoL) magic packet.
2. It is reachable from anywhere through [Tailscale](https://tailscale.com), without opening ports on your router.
3. You can control it with Remote Desktop (or an alternative).

**Estimated time:** 30–45 minutes.

---

## Requirements

| Item | Notes |
|---|---|
| PC connected by **Ethernet cable** | Wake-on-LAN over Wi-Fi is almost never supported from the powered-off state. |
| Windows 10 or 11 | **Pro, Enterprise or Education** for the built-in Remote Desktop host. On **Home**, use one of the [alternatives](#windows-home-alternatives). |
| Admin access to the PC | Needed for driver and power settings. |
| Admin access to your router | Needed for the DHCP reservation. |
| A second device on the same network | To test WoL locally before involving the ESP32. |

---

## Part A — BIOS/UEFI

### A1. Enter the BIOS/UEFI

1. Restart the PC and press the setup key repeatedly while it boots. It's usually **Del**, **F2**, **F10** or **F12**, depending on the manufacturer.
2. Alternatively, from Windows: **Settings → System → Recovery → Advanced startup → Restart now**, then **Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**.

### A2. Enable Wake-on-LAN

The option name and location depend on the manufacturer. Look for anything mentioning *Wake on LAN*, *PCI-E*, *PME* or *Network wake*:

| Manufacturer | Where to look (typical) | Setting |
|---|---|---|
| ASUS | Advanced → APM Configuration | **Power On By PCI-E** → Enabled |
| MSI | Settings → Advanced → Wake Up Event Setup | **Resume By PCI-E Device** → Enabled |
| Gigabyte | Settings → Platform Power | **Wake on LAN** → Enabled |
| ASRock | Advanced → ACPI Configuration | **PCIE Devices Power On** → Enabled |
| Dell | Power Management → Wake on LAN/WLAN | **LAN Only** |
| HP | Advanced → Power-On Options / Device Power Management | **S4/S5 Wake on LAN** → Enabled |
| Lenovo | Power | **Wake on LAN** → Enabled / Automatic |

> If you can't find it, search the internet for your motherboard model + "wake on lan".

### A3. Disable deep power-saving modes

These modes cut power to the network card when the PC is off, which makes WoL impossible:

| Option name | Set to |
|---|---|
| **ErP Ready** / ErP Support (ASUS, MSI, Gigabyte) | **Disabled** |
| **Deep Sleep** (ASRock, Dell) | **Disabled** |
| **EuP 2013** | **Disabled** |

### A4. (Recommended) Power behavior after a power outage

After a power cut, many PCs won't respond to WoL until they've been turned on at least once. Look for **Restore on AC Power Loss** / **AC Back** / **After Power Failure**:

- **Power Off** (default): the PC stays off. On some motherboards WoL still works; on others it doesn't until the next boot.
- **Last State**: the PC returns to the state it was in before the outage.

Test WoL after unplugging and re-plugging the PC to know how your hardware behaves.

### A5. Save and exit

Usually **F10 → Yes**.

---

## Part B — Windows

> Run the PowerShell commands in an **elevated** PowerShell window (right-click Start → **Terminal (Admin)**).

### B1. Identify the Ethernet adapter and its MAC address

```powershell
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, MacAddress, LinkSpeed
```

Write down:

- **Name** of the Ethernet adapter (e.g. `Ethernet`), used in the next steps.
- **MacAddress** (e.g. `AA-BB-CC-DD-EE-FF`), which goes into `PC_MAC` in the firmware's `config.h`.

### B2. Configure the network adapter for Wake-on-LAN

**Using the GUI:**

1. Open **Device Manager** (`devmgmt.msc`) → **Network adapters** → double-click your Ethernet adapter.
2. **Power Management** tab:
   - ☑ Allow this device to wake the computer
   - ☑ Only allow a magic packet to wake the computer
   - ☐ Allow the computer to turn off this device to save power (unchecking it is recommended, since it can cause issues on some adapters)
3. **Advanced** tab. Set the following if present (names vary by vendor):

| Property | Value | Typical vendor |
|---|---|---|
| Wake on Magic Packet | **Enabled** | All |
| Wake on pattern match | Disabled (avoids random wake-ups) | All |
| Shutdown Wake-On-Lan / Wake on LAN after shutdown | **Enabled** | Intel, Realtek |
| WOL & Shutdown Link Speed | **10 Mbps First** | Realtek |
| Energy Efficient Ethernet / Green Ethernet | **Disabled** | Realtek, Intel |

**Using PowerShell** (to check what's there):

```powershell
# Replace "Ethernet" with your adapter name from B1
Get-NetAdapterAdvancedProperty -Name "Ethernet" | Where-Object DisplayName -Match "Wake|WOL|Energy|Green" | Format-Table DisplayName, DisplayValue
Get-NetAdapterPowerManagement -Name "Ethernet"
```

Make sure the device is armed to wake the PC:

```powershell
powercfg /devicequery wake_armed
```

Your Ethernet adapter must appear in the list. If it doesn't:

```powershell
powercfg /deviceenablewake "Exact device name as shown in Device Manager"
```

### B3. Disable Fast Startup

**This is the #1 reason WoL fails from shutdown.** With Fast Startup enabled, "Shut down" is actually a hybrid hibernation that often leaves the network card unarmed.

**GUI:** Control Panel → **Power Options** → **Choose what the power buttons do** → **Change settings that are currently unavailable** → uncheck **Turn on fast startup** → **Save changes**.

**PowerShell:**

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -Value 0
```

### B4. Reserve a fixed IP for the PC in your router

The firmware's `/status` command checks the PC at a fixed IP address.

1. Find the current IP:
   ```powershell
   Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4 | Select-Object IPAddress
   ```
2. Log in to your router's admin page (often `http://192.168.0.1` or `http://192.168.1.1`, printed on the router's label).
3. Look for **DHCP reservation**, **Static lease**, **Address reservation** or **LAN → DHCP**.
4. Bind the PC's **MAC address** (B1) to its current IP.

This IP goes into `PC_IP_ADDRESS` in `config.h`.

### B5. Test Wake-on-LAN locally (before using the ESP32)

1. Shut down the PC with **Start → Power → Shut down**.
2. Wait about 30 seconds. Check that the Ethernet port LEDs (on the PC or on the router) are still on. If they're off, the card has no power: go back to [A3](#a3-disable-deep-power-saving-modes).
3. From a **second device on the same network**, send a magic packet:
   - **Another Windows PC:** use [`tools/Send-MagicPacket.ps1`](../tools/Send-MagicPacket.ps1) from this repository:
     ```powershell
     powershell -ExecutionPolicy Bypass -File .\tools\Send-MagicPacket.ps1 -MacAddress "AA:BB:CC:DD:EE:FF"
     ```
   - **Phone:** any "Wake On Lan" app from the app store.
4. The PC should power on within a few seconds.

Also test waking from **Sleep** if you plan to use it. Once local WoL works, the ESP32 will work too.

---

## Part C — Remote access with Tailscale

Tailscale creates a private, encrypted network between your devices. It works behind CGNAT and **doesn't require opening any ports** on your router.

In this setup the PC is a **regular Tailscale node**. Only the PC is reachable, not the rest of your network, and it doesn't route anyone else's traffic.

### C1. Install and sign in

1. Download and install Tailscale from <https://tailscale.com/download/windows>, or:
   ```powershell
   winget install --id tailscale.tailscale -e
   ```
2. Click the Tailscale icon in the system tray → **Log in** and sign in (Google, Microsoft, GitHub, etc.).
3. Install Tailscale on your phone/laptop and sign in with **the same account**.

### C2. Keep the PC connected when nobody is logged in

After a Wake-on-LAN boot, the PC sits at the login screen with no user signed in. By default Tailscale on Windows disconnects in that state.

- Tailscale tray icon → **Preferences** → enable **Run unattended**.

### C3. Disable key expiry for the PC

Tailscale keys expire periodically (180 days by default) and require signing in again **on the PC**, which you can't do remotely.

1. Open the admin console: <https://login.tailscale.com/admin/machines>
2. Find the PC → **⋯** menu → **Disable key expiry**.

### C4. Note the PC's Tailscale name

In the admin console (or `tailscale status` on the PC) note the machine name and its `100.x.y.z` IP. With **MagicDNS** (enabled by default) you can connect by name, e.g. `my-desktop`.

---

## Part D — Remote Desktop

### D1. Enable Remote Desktop (Windows Pro/Enterprise/Education)

1. **Settings → System → Remote Desktop** → turn **On** → **Confirm**.
2. Keep **"Require devices to use Network Level Authentication"** enabled.

PowerShell equivalent:

```powershell
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

### D2. Microsoft account sign-in

If you sign in to Windows with a **Microsoft account**, Remote Desktop needs the **account email and password**, not your PIN.

If your account is set up as passwordless (Windows Hello only), Remote Desktop will reject your credentials. To fix it:

1. **Settings → Accounts → Sign-in options** → turn **off** "For improved security, only allow Windows Hello sign-in for Microsoft accounts on this device".
2. Sign out and sign in once **with your password** (not the PIN).

### D3. Connect from anywhere

1. Make sure Tailscale is connected on your phone/laptop.
2. Use the **Windows App** (formerly *Microsoft Remote Desktop*) on Windows, macOS, iOS or Android, or `mstsc` on Windows.
3. Connect to the PC's Tailscale name (`my-desktop`) or its `100.x.y.z` IP.

> ⚠️ **Never** forward port 3389 on your router to expose Remote Desktop directly to the internet. It's constantly scanned and attacked. Always go through Tailscale.

### Windows Home alternatives

Windows Home can't host Remote Desktop sessions. Use one of these instead (all work over Tailscale or on their own):

| Tool | Best for |
|---|---|
| [RustDesk](https://rustdesk.com) | Open source; can connect directly over the Tailscale IP |
| [Parsec](https://parsec.app) | Low latency, gaming, multiple monitors |
| [Chrome Remote Desktop](https://remotedesktop.google.com) | Simplest setup |

Make sure the tool you pick is configured to **start with Windows and work at the login screen** (unattended access). Otherwise it won't be reachable after a WoL boot.

---

## Part E — (Optional) Save power when you're done

To let the PC turn itself off after you disconnect:

- **Settings → System → Power & battery → Screen and sleep**: set the PC to **sleep after N minutes** when plugged in. You can wake it again with `/wake`.
- Or shut it down from the remote session: **Start → Power → Shut down**, or `shutdown /s /t 0`.

---

## Verification checklist

- [ ] WoL enabled in BIOS; ErP / Deep Sleep disabled
- [ ] Adapter: "Allow this device to wake the computer" + "Only allow a magic packet" checked
- [ ] Adapter: "Wake on Magic Packet" enabled
- [ ] Fast Startup disabled
- [ ] DHCP reservation created; MAC and IP written down
- [ ] Local WoL test from a second device works from **shutdown**
- [ ] Tailscale installed, **Run unattended** on, **key expiry disabled**
- [ ] Remote Desktop (or alternative) works over Tailscale from outside your home network (e.g. phone on mobile data)

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| PC doesn't wake from shutdown but wakes from sleep | Fast Startup still on (B3), or "Shutdown Wake-On-Lan" disabled (B2) |
| Ethernet LEDs go dark when the PC is off | ErP Ready / Deep Sleep enabled in BIOS (A3) |
| WoL worked, then stopped after a Windows update | Windows Update replaced the network driver and reset its settings. Repeat B2, or install the driver from the motherboard vendor's website. |
| WoL stops working after a power outage | Hardware limitation; see A4 |
| Works locally but not with the ESP32 | ESP32 on a different subnet/VLAN or on a guest network. It must be on the same LAN as the PC. |
| Remote Desktop "credentials did not work" | See D2 |
| Can't reach the PC through Tailscale after a reboot | "Run unattended" not enabled (C2) |
