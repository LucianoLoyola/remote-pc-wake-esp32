/*
  remote-pc-wake — Wake your PC from anywhere with an ESP32 and a Telegram bot.

  Telegram commands:
    /wake    Send a Wake-on-LAN magic packet to the PC
    /status  Check whether the PC is on
    /help    Show available commands

  Required libraries (Arduino IDE -> Library Manager):
    - UniversalTelegramBot (by Brian Lough)
    - ArduinoJson (by Benoit Blanchon)

  Setup: copy config.example.h to config.h and fill in your values.
  Docs: see the docs/ folder in the repository.
*/

#if __has_include("config.h")
#include "config.h"
#else
#error "config.h not found. Copy config.example.h to config.h and fill in your values."
#endif

#include <WiFi.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <UniversalTelegramBot.h>

const unsigned long POLL_INTERVAL_MS = POLL_INTERVAL_SECONDS * 1000UL;
const unsigned long WAKE_CHECK_INTERVAL_MS = 5000;
const unsigned long IDLE_DELAY_MS = 200;  // lets the CPU idle between loop iterations
const unsigned long WIFI_CONNECT_TIMEOUT_MS = 30000;
const uint16_t WOL_PORT = 9;

WiFiUDP udp;
WiFiClientSecure secureClient;
UniversalTelegramBot bot(BOT_TOKEN, secureClient);

uint8_t pcMac[6];
IPAddress pcIp;

unsigned long lastPoll = 0;

// Pending wake check: after /wake, poll the PC until it answers or we time out.
bool wakePending = false;
unsigned long wakeSentAt = 0;
unsigned long lastWakeCheck = 0;

bool parseMac(const char* text, uint8_t* mac) {
  unsigned int b[6];
  if (sscanf(text, "%x%*c%x%*c%x%*c%x%*c%x%*c%x", &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6) {
    return false;
  }
  for (int i = 0; i < 6; i++) {
    mac[i] = (uint8_t)b[i];
  }
  return true;
}

void sendMagicPacket() {
  // Magic packet: 6 bytes of 0xFF followed by the target MAC repeated 16 times.
  uint8_t packet[102];
  memset(packet, 0xFF, 6);
  for (int i = 0; i < 16; i++) {
    memcpy(packet + 6 + i * 6, pcMac, 6);
  }

  // Subnet broadcast address, e.g. 192.168.1.255
  IPAddress ip = WiFi.localIP();
  IPAddress mask = WiFi.subnetMask();
  IPAddress broadcast(ip[0] | ~mask[0], ip[1] | ~mask[1], ip[2] | ~mask[2], ip[3] | ~mask[3]);

  // Send a few copies in case one gets lost.
  for (int i = 0; i < 3; i++) {
    udp.beginPacket(broadcast, WOL_PORT);
    udp.write(packet, sizeof(packet));
    udp.endPacket();
    delay(100);
  }
  Serial.println("Magic packet sent.");
}

bool isPcOnline() {
  WiFiClient client;
  bool online = client.connect(pcIp, PC_CHECK_PORT, 1500);
  client.stop();
  return online;
}

void reply(const String& text) {
  bot.sendMessage(ALLOWED_CHAT_ID, text, "");
}

void handleMessages(int count) {
  for (int i = 0; i < count; i++) {
    String chatId = bot.messages[i].chat_id;
    String text = bot.messages[i].text;
    text.trim();

    // Commands may arrive as "/wake@YourBotName" in group chats.
    int at = text.indexOf('@');
    if (at > 0) {
      text = text.substring(0, at);
    }

    if (chatId != ALLOWED_CHAT_ID) {
      Serial.println("Ignored message from unauthorized chat " + chatId);
      bot.sendMessage(chatId, "Not authorized.", "");
      continue;
    }

    if (text == "/wake") {
      if (isPcOnline()) {
        reply("The PC is already on.");
        continue;
      }
      sendMagicPacket();
      wakePending = true;
      wakeSentAt = millis();
      lastWakeCheck = millis();
      reply("Magic packet sent. I'll let you know when the PC is online...");
    } else if (text == "/status") {
      reply(isPcOnline() ? "🟢 PC is on" : "🔴 PC is off (or not responding)");
    } else {
      reply("Commands:\n/wake - turn on the PC\n/status - check whether the PC is on");
    }
  }
}

void checkPendingWake() {
  if (!wakePending || millis() - lastWakeCheck < WAKE_CHECK_INTERVAL_MS) {
    return;
  }
  lastWakeCheck = millis();

  if (isPcOnline()) {
    wakePending = false;
    unsigned long seconds = (millis() - wakeSentAt) / 1000;
    reply("✅ The PC is online (took " + String(seconds) + " s).");
  } else if (millis() - wakeSentAt > WAKE_TIMEOUT_SECONDS * 1000UL) {
    wakePending = false;
    reply("⚠️ The PC did not respond after " + String(WAKE_TIMEOUT_SECONDS) +
          " s. Check the troubleshooting section of the PC setup runbook.");
  }
}

void connectWifi() {
  WiFi.persistent(false);  // don't write credentials to flash on every connect
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(DEVICE_HOSTNAME);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  WiFi.setSleep(true);  // modem sleep: radio powers down between router beacons
  WiFi.setTxPower(WIFI_TX_POWER);
  Serial.print("Connecting to Wi-Fi");
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > WIFI_CONNECT_TIMEOUT_MS) {
      Serial.println("\nWi-Fi connection timed out. Restarting...");
      ESP.restart();
    }
    delay(500);
    Serial.print(".");
  }
  Serial.print("\nConnected. IP: ");
  Serial.println(WiFi.localIP());
}

void setup() {
  Serial.begin(115200);
  delay(500);

  // 80 MHz is the lowest frequency that keeps Wi-Fi working; plenty for this job.
  setCpuFrequencyMhz(CPU_FREQUENCY_MHZ);

  if (!parseMac(PC_MAC, pcMac)) {
    Serial.println("Invalid PC_MAC in config.h. Expected format AA:BB:CC:DD:EE:FF");
    while (true) {
      delay(1000);
    }
  }
  if (!pcIp.fromString(PC_IP_ADDRESS)) {
    Serial.println("Invalid PC_IP_ADDRESS in config.h.");
    while (true) {
      delay(1000);
    }
  }

  connectWifi();
  secureClient.setCACert(TELEGRAM_CERTIFICATE_ROOT);

  // Discard messages sent while the ESP32 was offline, so an old /wake
  // doesn't turn on the PC unexpectedly after a power outage.
  bot.getUpdates(-1);

  bot.setMyCommands(F("[{\"command\":\"wake\",\"description\":\"Turn on the PC\"},"
                      "{\"command\":\"status\",\"description\":\"Check whether the PC is on\"},"
                      "{\"command\":\"help\",\"description\":\"Show available commands\"}]"));
  reply("🤖 ESP32 online. Use /wake or /status.");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWifi();
  }

  if (millis() - lastPoll > POLL_INTERVAL_MS) {
    int count = bot.getUpdates(bot.last_message_received + 1);
    while (count) {
      handleMessages(count);
      count = bot.getUpdates(bot.last_message_received + 1);
    }
    lastPoll = millis();
  }

  checkPendingWake();

  delay(IDLE_DELAY_MS);
}
