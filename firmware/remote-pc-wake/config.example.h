// Copy this file to "config.h" (same folder) and fill in your values.
// config.h is ignored by Git so your secrets never end up in the repository.

#pragma once

// ---------- Wi-Fi ----------
// The ESP32 only supports 2.4 GHz networks.
#define WIFI_SSID     "YOUR_WIFI_NAME"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// ---------- Fixed IP for the ESP32 (optional) ----------
// Leave ESP32_STATIC_IP empty to get an address from the router (DHCP), which is
// the best option when you can reserve the address in the router.
// If your router can't reserve addresses, set a fixed one here. Use an address
// outside the range the router hands out, and that no other device uses.
#define ESP32_STATIC_IP ""
#define NETWORK_GATEWAY ""                // your router, e.g. "192.168.1.1"
#define NETWORK_SUBNET  "255.255.255.0"
#define NETWORK_DNS     ""                // empty = use the router

// ---------- Telegram ----------
// Bot token from @BotFather.
#define BOT_TOKEN "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ"

// Your numeric Telegram user ID (get it from @userinfobot).
// The bot ignores commands from anyone else.
#define ALLOWED_CHAT_ID "123456789"

// ---------- Target PC ----------
// MAC address of the PC's Ethernet adapter ("Physical Address" in `ipconfig /all`).
// Both "AA:BB:CC:DD:EE:FF" and "AA-BB-CC-DD-EE-FF" are accepted.
#define PC_MAC "AA:BB:CC:DD:EE:FF"

// Fixed LAN IP of the PC: reserve it in your router's DHCP settings,
// or set it on the PC with scripts\Set-StaticIp.ps1.
#define PC_IP_ADDRESS "192.168.1.100"

// TCP port used by /status to check whether the PC is on.
// 3389 = Remote Desktop, 445 = Windows file sharing.
#define PC_CHECK_PORT 3389

// ---------- PC agent (optional, see docs/05-pc-agent.md) ----------
// Enables /shutdown, /restart, /sleep, /lock, /cancel, PC stats and agent warnings.
// Install-Agent.ps1 prints both values. Leave the token empty to disable these features.
#define AGENT_TOKEN ""
#define AGENT_PORT  8765

// ---------- Notifications ----------
// How often the ESP32 checks whether the PC is on (seconds).
#define MONITOR_INTERVAL_SECONDS 30

// Alert when the PC turns on / goes offline without being asked through the bot or web UI.
#define NOTIFY_UNEXPECTED_POWER_ON  true
#define NOTIFY_UNEXPECTED_POWER_OFF true

// Forward warnings from the agent (disk almost full, Windows Update restart pending).
#define NOTIFY_AGENT_WARNINGS true

// ---------- Web UI (home network only) ----------
// Open http://remote-pc-wake.local (see DEVICE_HOSTNAME) in a browser on your home network.
// The web UI is disabled while WEB_PASSWORD is empty.
#define WEB_USERNAME "admin"
#define WEB_PASSWORD ""

// ---------- Optional ----------
// Name the ESP32 shows on your network.
#define DEVICE_HOSTNAME "remote-pc-wake"

// How long to wait for the PC to come online after /wake (seconds).
#define WAKE_TIMEOUT_SECONDS 120

// ---------- Power saving ----------
// How often the ESP32 asks Telegram for new commands (seconds).
// Higher = less power and network traffic, but /wake takes up to this long to react.
#define POLL_INTERVAL_SECONDS 15

// CPU clock: 80, 160 or 240 MHz. 80 is the minimum that supports Wi-Fi.
#define CPU_FREQUENCY_MHZ 80

// Wi-Fi transmit power. The ESP32 sits next to the router, so a low value is enough.
// If the connection is unstable, raise it: WIFI_POWER_15dBm, WIFI_POWER_19_5dBm (max).
#define WIFI_TX_POWER WIFI_POWER_11dBm
