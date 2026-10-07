// Copy this file to "config.h" (same folder) and fill in your values.
// config.h is ignored by Git so your secrets never end up in the repository.

#pragma once

// ---------- Wi-Fi ----------
// The ESP32 only supports 2.4 GHz networks.
#define WIFI_SSID     "YOUR_WIFI_NAME"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

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

// Fixed LAN IP of the PC (reserve it in your router's DHCP settings).
#define PC_IP_ADDRESS "192.168.1.100"

// TCP port used by /status to check whether the PC is on.
// 3389 = Remote Desktop, 445 = Windows file sharing.
#define PC_CHECK_PORT 3389

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
