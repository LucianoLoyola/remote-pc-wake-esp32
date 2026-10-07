# Runbook 01 — PC setup (BIOS/UEFI and Windows)

This runbook prepares the **target PC** (the one you want to turn on remotely) so that it can be powered on by a Wake-on-LAN (WoL) magic packet.

Remote control once the PC is on is covered in [Runbook 04](04-remote-access-tailscale.md).

**Estimated time:** 20–30 minutes.

---

## Requirements

| Item | Notes |
|---|---|
| PC connected by **Ethernet cable** | Wake-on-LAN over Wi-Fi is almost never supported from the powered-off state. |
| Windows 10 or 11 | Any edition |
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

### Automatic (recommended)

In an **elevated** PowerShell window (right-click Start → **Terminal (Admin)**), from the repository folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Enable-WakeOnLan.ps1
```

The script does B1–B3: it configures the Ethernet adapter, arms it to wake the PC, disables Fast Startup, and checks the result. At the end it prints the **MAC** and **IP** for B4. The network drops for a few seconds while the adapter restarts.

To only check the current configuration without changing anything (no Administrator needed):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Enable-WakeOnLan.ps1 -CheckOnly
```

Then continue with [B4](#b4-reserve-a-fixed-ip-for-the-pc-in-your-router) (router) and [B5](#b5-test-wake-on-lan-locally-before-using-the-esp32) (test).

### Manual

Run the PowerShell commands below in an **elevated** PowerShell window.

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
   - **Checked:** Allow this device to wake the computer
   - **Checked:** Only allow a magic packet to wake the computer
   - **Unchecked:** Allow the computer to turn off this device to save power (unchecking it is recommended, since it can cause issues on some adapters)
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
   - **Another Windows PC:** use [`scripts/Send-MagicPacket.ps1`](../scripts/Send-MagicPacket.ps1) from this repository:
     ```powershell
     powershell -ExecutionPolicy Bypass -File .\scripts\Send-MagicPacket.ps1 -MacAddress "AA:BB:CC:DD:EE:FF"
     ```
   - **Phone:** any "Wake On Lan" app from the app store.
4. The PC should power on within a few seconds.

Also test waking from **Sleep** if you plan to use it. Once local WoL works, the ESP32 will work too.

---

## Next step

The PC can now be powered on remotely. To control it once it's on, continue with [Runbook 04 — Remote access with Tailscale and Remote Desktop](04-remote-access-tailscale.md).

---

## Verification checklist

- [ ] WoL enabled in BIOS; ErP / Deep Sleep disabled
- [ ] Adapter: "Allow this device to wake the computer" + "Only allow a magic packet" checked
- [ ] Adapter: "Wake on Magic Packet" enabled
- [ ] Fast Startup disabled
- [ ] DHCP reservation created; MAC and IP written down
- [ ] Local WoL test from a second device works from **shutdown**

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| PC doesn't wake from shutdown but wakes from sleep | Fast Startup still on (B3), or "Shutdown Wake-On-Lan" disabled (B2) |
| Ethernet LEDs go dark when the PC is off | ErP Ready / Deep Sleep enabled in BIOS (A3) |
| WoL worked, then stopped after a Windows update | Windows Update replaced the network driver and reset its settings. Repeat B2, or install the driver from the motherboard vendor's website. |
| WoL stops working after a power outage | Hardware limitation; see A4 |
| Works locally but not with the ESP32 | ESP32 on a different subnet/VLAN or on a guest network. It must be on the same LAN as the PC. |
