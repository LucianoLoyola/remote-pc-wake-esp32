/*
  remote-pc-wake — Wake and control your PC from anywhere with an ESP32 and a Telegram bot.

  Telegram commands:
    /wake               Send a Wake-on-LAN magic packet to the PC
    /status             PC status and stats
    /shutdown [min]     Shut down the PC (now, or in N minutes)        [agent]
    /restart [min]      Restart the PC                                 [agent]
    /sleep              Put the PC to sleep                            [agent]
    /lock               Lock the PC's screen                           [agent]
    /cancel             Cancel a scheduled shutdown/restart            [agent]
    /menu               Show buttons for all actions
  [agent] = requires the PC agent (see docs/05-pc-agent.md)

  Also serves a web UI on the local network: http://<DEVICE_HOSTNAME>.local

  Required libraries (Arduino IDE -> Library Manager):
    - UniversalTelegramBot (by Brian Lough)
    - ArduinoJson 7 (by Benoit Blanchon)

  Setup: copy config.example.h to config.h and fill in your values.
  Docs: see the docs/ folder in the repository.
*/

#if __has_include("config.h")
#include "config.h"
#else
#error "config.h not found. Copy config.example.h to config.h and fill in your values."
#endif

// Defaults for settings added after the first release, so older config.h files keep compiling.
#ifndef AGENT_TOKEN
#define AGENT_TOKEN ""
#endif
#ifndef AGENT_PORT
#define AGENT_PORT 8765
#endif
#ifndef MONITOR_INTERVAL_SECONDS
#define MONITOR_INTERVAL_SECONDS 30
#endif
#ifndef NOTIFY_UNEXPECTED_POWER_ON
#define NOTIFY_UNEXPECTED_POWER_ON true
#endif
#ifndef NOTIFY_UNEXPECTED_POWER_OFF
#define NOTIFY_UNEXPECTED_POWER_OFF true
#endif
#ifndef NOTIFY_AGENT_WARNINGS
#define NOTIFY_AGENT_WARNINGS true
#endif
#ifndef WEB_USERNAME
#define WEB_USERNAME "admin"
#endif
#ifndef WEB_PASSWORD
#define WEB_PASSWORD ""
#endif
#ifndef ESP32_STATIC_IP
#define ESP32_STATIC_IP ""
#endif
#ifndef NETWORK_GATEWAY
#define NETWORK_GATEWAY ""
#endif
#ifndef NETWORK_SUBNET
#define NETWORK_SUBNET "255.255.255.0"
#endif
#ifndef NETWORK_DNS
#define NETWORK_DNS ""
#endif

#include <WiFi.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <UniversalTelegramBot.h>
#include <ArduinoJson.h>
#include "web_ui.h"

#define FIRMWARE_VERSION "1.2.1"

const unsigned long POLL_INTERVAL_MS = POLL_INTERVAL_SECONDS * 1000UL;
const unsigned long MONITOR_INTERVAL_MS = MONITOR_INTERVAL_SECONDS * 1000UL;
const unsigned long FAST_PROBE_INTERVAL_MS = 5000;           // while waiting for a power change
const unsigned long POWER_CHANGE_TIMEOUT_MS = 10 * 60000UL;  // shutdown/restart/sleep must happen within this
const unsigned long IDLE_DELAY_MS = 200;                     // lets the CPU idle between loop iterations
const unsigned long WIFI_CONNECT_TIMEOUT_MS = 30000;
const long MAX_ACTION_DELAY_SECONDS = 86400;
const uint16_t WOL_PORT = 9;

// A new PC state must be seen this many probes in a row before it's accepted,
// so a single lost packet doesn't trigger a false alert.
const int STABLE_PROBES = 2;
const int STABLE_PROBES_AGENT_DOWN = 4;  // the agent may start a bit after Windows

WiFiUDP udp;
WiFiClientSecure secureClient;
UniversalTelegramBot bot(BOT_TOKEN, secureClient);
WebServer server(80);
bool webEnabled = false;

uint8_t pcMac[6];
IPAddress pcIp;

unsigned long lastPoll = 0;
unsigned long lastProbe = 0;

// ---------- PC state ----------

enum PcState { PC_UNKNOWN, PC_OFF, PC_ON, PC_AGENT_DOWN };

PcState pcState = PC_UNKNOWN;
PcState candidateState = PC_UNKNOWN;
int candidateCount = 0;

String lastAgentJson;   // last /api/status body, empty when the agent didn't answer
String lastAgentError;  // why the last agent request failed
bool agentDownNotified = false;
String sentWarnings;    // agent warnings already notified since the PC was turned on

// ---------- Expected power changes ----------
// Requests made through the bot or the web UI, so state changes can be reported
// as "done" instead of "unexpected".

enum Expectation { EXPECT_NONE, EXPECT_ON, EXPECT_OFF, EXPECT_RESTART };

Expectation expectation = EXPECT_NONE;
unsigned long expectationStart = 0;
unsigned long expectationDelayMs = 0;    // the change is not due before this
unsigned long expectationTimeoutMs = 0;  // give up this long after it's due
String expectationLabel;                 // e.g. "shut down", "go to sleep"
long uptimeBeforeRestart = 0;

bool agentEnabled() {
  return strlen(AGENT_TOKEN) > 0;
}

bool isOn(PcState state) {
  return state == PC_ON || state == PC_AGENT_DOWN;
}

const char* stateName(PcState state) {
  switch (state) {
    case PC_ON: return "on";
    case PC_OFF: return "off";
    case PC_AGENT_DOWN: return "agent_down";
    default: return "unknown";
  }
}

const char* expectationName() {
  switch (expectation) {
    case EXPECT_ON: return "wake";
    case EXPECT_OFF: return "off";
    case EXPECT_RESTART: return "restart";
    default: return "none";
  }
}

void expect(Expectation what, unsigned long delayMs, unsigned long timeoutMs, const String& label) {
  expectation = what;
  expectationStart = millis();
  expectationDelayMs = delayMs;
  expectationTimeoutMs = timeoutMs;
  expectationLabel = label;
}

bool expectationDue() {
  return expectation != EXPECT_NONE && millis() - expectationStart >= expectationDelayMs;
}

String formatDuration(long seconds) {
  long days = seconds / 86400;
  long hours = (seconds % 86400) / 3600;
  long minutes = (seconds % 3600) / 60;
  if (days > 0) return String(days) + "d " + String(hours) + "h";
  if (hours > 0) return String(hours) + "h " + String(minutes) + "m";
  return String(minutes) + "m";
}

void notify(const String& text) {
  bot.sendMessage(ALLOWED_CHAT_ID, text, "");
}

// ---------- Network helpers ----------

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

bool isPortOpen() {
  WiFiClient client;
  bool open = client.connect(pcIp, PC_CHECK_PORT, 1500);
  client.stop();
  return open;
}

// Sends a request to the PC agent. Returns the HTTP status code, or a negative value
// if the agent could not be reached.
int agentRequest(const char* method, const String& path, String& body) {
  WiFiClient client;
  HTTPClient http;
  http.setConnectTimeout(1500);
  http.setTimeout(5000);
  if (!http.begin(client, pcIp.toString(), AGENT_PORT, path)) {
    return -1;
  }
  http.addHeader("X-Agent-Token", AGENT_TOKEN);
  int code;
  if (strcmp(method, "POST") == 0) {
    // Windows' HTTP server rejects a POST without Content-Length (HTTP 411), and HTTPClient
    // only sends that header when there's a body, so send an empty JSON object.
    http.addHeader("Content-Type", "application/json");
    code = http.sendRequest(method, String("{}"));
  } else {
    code = http.sendRequest(method, String());
  }
  if (code > 0) {
    body = http.getString();
  }
  http.end();
  return code;
}

PcState probePc() {
  lastAgentJson = "";
  if (agentEnabled()) {
    String body;
    int code = agentRequest("GET", "/api/status", body);
    if (code == 200) {
      lastAgentJson = body;
      lastAgentError = "";
      return PC_ON;
    }
    if (code == 401) {
      lastAgentError = "wrong token (check AGENT_TOKEN)";
    } else if (code > 0) {
      lastAgentError = "HTTP " + String(code);
    } else {
      lastAgentError = "no response";
    }
  }
  if (isPortOpen()) {
    return agentEnabled() ? PC_AGENT_DOWN : PC_ON;
  }
  return PC_OFF;
}

// ---------- Monitoring and notifications ----------

void onStateChange(PcState previous, PcState current) {
  Serial.printf("PC state: %s -> %s\n", stateName(previous), stateName(current));

  if (!isOn(previous) && isOn(current)) {
    sentWarnings = "";
    if (expectation == EXPECT_ON) {
      unsigned long seconds = (millis() - expectationStart) / 1000;
      notify("✅ The PC is online (took " + String(seconds) + " s).");
      expectation = EXPECT_NONE;
    } else if (expectation != EXPECT_RESTART && NOTIFY_UNEXPECTED_POWER_ON) {
      notify("🚨 The PC was turned on, but not from the bot.");
    }
  }

  if (isOn(previous) && !isOn(current)) {
    agentDownNotified = false;
    if (expectation == EXPECT_OFF) {
      notify(expectationLabel == "go to sleep" ? "💤 The PC is asleep." : "⏻ The PC has shut down.");
      expectation = EXPECT_NONE;
    } else if (expectation != EXPECT_RESTART && NOTIFY_UNEXPECTED_POWER_OFF) {
      notify("⚠️ The PC went offline, but not from the bot. It was shut down at the PC, crashed, or lost its network connection.");
    }
  }

  if (current == PC_AGENT_DOWN) {
    notify("⚠️ The PC is on, but the agent is not responding (" + lastAgentError + "). Power actions are unavailable.");
    agentDownNotified = true;
  } else if (current == PC_ON && agentDownNotified) {
    notify("✅ The PC agent is responding again.");
    agentDownNotified = false;
  }
}

void checkAgentReport(JsonDocument& report) {
  if (expectation == EXPECT_RESTART && expectationDue()) {
    long uptime = report["uptimeSeconds"] | 0L;
    if (uptime < uptimeBeforeRestart) {
      notify("🔄 The PC restarted and is back online.");
      expectation = EXPECT_NONE;
    }
  }

  if (NOTIFY_AGENT_WARNINGS) {
    for (JsonVariant warning : report["warnings"].as<JsonArray>()) {
      String text = warning.as<String>();
      if (sentWarnings.indexOf(text) < 0) {
        notify("⚠️ " + text);
        sentWarnings += text + "\n";
      }
    }
  }
}

void monitorPc() {
  PcState observed = probePc();

  if (observed == PC_ON && !lastAgentJson.isEmpty()) {
    JsonDocument report;
    if (!deserializeJson(report, lastAgentJson)) {
      checkAgentReport(report);
    }
  }

  if (pcState == PC_UNKNOWN) {
    pcState = observed;
    return;
  }
  if (observed == pcState) {
    candidateCount = 0;
    return;
  }

  if (observed != candidateState) {
    candidateState = observed;
    candidateCount = 0;
  }
  candidateCount++;
  int required = observed == PC_AGENT_DOWN ? STABLE_PROBES_AGENT_DOWN : STABLE_PROBES;
  if (candidateCount >= required) {
    PcState previous = pcState;
    pcState = observed;
    candidateCount = 0;
    onStateChange(previous, observed);
  }
}

void checkExpectationTimeout() {
  if (expectation == EXPECT_NONE) {
    return;
  }
  if (millis() - expectationStart < expectationDelayMs + expectationTimeoutMs) {
    return;
  }
  switch (expectation) {
    case EXPECT_ON:
      notify("⚠️ The PC did not come online after " + String(WAKE_TIMEOUT_SECONDS) +
             " s. Check the troubleshooting section of Runbook 01.");
      break;
    case EXPECT_OFF:
      notify("⚠️ The PC is still on, although it was asked to " + expectationLabel + ".");
      break;
    case EXPECT_RESTART:
      notify("⚠️ The PC did not restart as requested.");
      break;
    default:
      break;
  }
  expectation = EXPECT_NONE;
}

String formatStatus(PcState state) {
  if (state == PC_OFF) {
    return expectation == EXPECT_ON ? "🟡 PC is waking up…" : "🔴 PC is off";
  }
  if (state == PC_AGENT_DOWN) {
    return "🟠 PC is on, but the agent is not responding (" + lastAgentError + ")";
  }

  JsonDocument report;
  if (lastAgentJson.isEmpty() || deserializeJson(report, lastAgentJson)) {
    return "🟢 PC is on";
  }

  String text = "🟢 PC is on: " + report["hostname"].as<String>() + "\n";
  if (!report["user"].isNull()) {
    String user = report["user"].as<String>();
    text += "👤 " + user.substring(user.lastIndexOf('\\') + 1) + "\n";  // "PC\user" -> "user"
  }
  text += "⏱ Up " + formatDuration(report["uptimeSeconds"] | 0L) + "\n";
  text += "🧠 CPU " + String(report["cpuPercent"] | 0) + "% · RAM " + String(report["memory"]["usedPercent"] | 0) +
          "% of " + String(report["memory"]["totalGB"] | 0.0f, 1) + " GB\n";
  if (!report["gpu"].isNull()) {
    text += "🎮 " + report["gpu"]["name"].as<String>() + " · " + String(report["gpu"]["temperatureC"] | 0) +
            " °C · " + String(report["gpu"]["utilizationPercent"] | 0) + "%\n";
  }
  for (JsonVariant disk : report["disks"].as<JsonArray>()) {
    text += "💾 " + disk["drive"].as<String>() + " " + String(disk["usedPercent"] | 0) + "% used, " +
            String(disk["freeGB"] | 0.0f, 1) + " GB free\n";
  }
  if (!report["pendingAction"].isNull()) {
    text += "⏰ Scheduled " + report["pendingAction"]["action"].as<String>() + " in " +
            formatDuration(report["pendingAction"]["secondsRemaining"] | 0L) + "\n";
  }
  for (JsonVariant warning : report["warnings"].as<JsonArray>()) {
    text += "⚠️ " + warning.as<String>() + "\n";
  }
  return text;
}

// ---------- Actions (shared by Telegram and the web UI) ----------

String runAction(const String& action, long delaySeconds, bool& ok) {
  ok = false;

  if (action == "wake") {
    if (isOn(probePc())) {
      ok = true;
      return "The PC is already on.";
    }
    sendMagicPacket();
    expect(EXPECT_ON, 0, WAKE_TIMEOUT_SECONDS * 1000UL, "wake up");
    ok = true;
    return "Magic packet sent. I'll let you know when the PC is online…";
  }

  if (action != "shutdown" && action != "restart" && action != "sleep" && action != "lock" && action != "cancel") {
    return "Unknown action.";
  }
  if (!agentEnabled()) {
    return "The PC agent is not configured. See docs/05-pc-agent.md.";
  }
  if (delaySeconds < 0 || delaySeconds > MAX_ACTION_DELAY_SECONDS) {
    return "The delay must be between 0 and 24 hours.";
  }

  String path = "/api/" + action;
  bool delayable = action == "shutdown" || action == "restart";
  if (delayable && delaySeconds > 0) {
    path += "?delay=" + String(delaySeconds);
  }

  String body;
  int code = agentRequest("POST", path, body);
  if (code < 0) {
    return "Could not reach the PC agent. Is the PC on?";
  }
  if (code == 401) {
    return "The agent rejected the token. Check AGENT_TOKEN in config.h.";
  }

  JsonDocument response;
  deserializeJson(response, body);
  String message = response["message"] | "";
  if (code != 200) {
    String detail = message.length() ? ": " + message : String();
    return "Agent error (HTTP " + String(code) + ")" + detail;
  }

  unsigned long delayMs = delayable ? delaySeconds * 1000UL : 0;
  if (action == "shutdown") {
    expect(EXPECT_OFF, delayMs, POWER_CHANGE_TIMEOUT_MS, "shut down");
  } else if (action == "sleep") {
    expect(EXPECT_OFF, 0, POWER_CHANGE_TIMEOUT_MS, "go to sleep");
  } else if (action == "restart") {
    uptimeBeforeRestart = response["uptimeSeconds"] | 0L;
    expect(EXPECT_RESTART, delayMs, POWER_CHANGE_TIMEOUT_MS, "restart");
  } else if (action == "cancel" && (expectation == EXPECT_OFF || expectation == EXPECT_RESTART)) {
    expectation = EXPECT_NONE;
  }

  ok = true;
  return message.length() ? message : String("Done.");
}

// ---------- Telegram ----------

const char* MENU_KEYBOARD =
    "[[{\"text\":\"⚡ Wake\",\"callback_data\":\"/wake\"},{\"text\":\"📊 Status\",\"callback_data\":\"/status\"}],"
    "[{\"text\":\"🔒 Lock\",\"callback_data\":\"/lock\"},{\"text\":\"💤 Sleep\",\"callback_data\":\"/sleep\"}],"
    "[{\"text\":\"🔄 Restart\",\"callback_data\":\"/restart\"},{\"text\":\"⏻ Shut down\",\"callback_data\":\"/shutdown\"}]]";

const char* SHUTDOWN_KEYBOARD =
    "[[{\"text\":\"Now\",\"callback_data\":\"do:shutdown:0\"},"
    "{\"text\":\"In 30 min\",\"callback_data\":\"do:shutdown:1800\"},"
    "{\"text\":\"In 1 h\",\"callback_data\":\"do:shutdown:3600\"}],"
    "[{\"text\":\"✖ Cancel\",\"callback_data\":\"do:dismiss:0\"}]]";

const char* RESTART_KEYBOARD =
    "[[{\"text\":\"Restart now\",\"callback_data\":\"do:restart:0\"},"
    "{\"text\":\"✖ Cancel\",\"callback_data\":\"do:dismiss:0\"}]]";

const char* HELP_TEXT =
    "Commands:\n"
    "/wake - turn on the PC\n"
    "/status - is it on? CPU, RAM, disks\n"
    "/shutdown [min] - shut down (now or in N min)\n"
    "/restart [min] - restart\n"
    "/sleep - put to sleep\n"
    "/lock - lock the screen\n"
    "/cancel - cancel a scheduled shutdown/restart\n"
    "/menu - buttons for everything";

void reply(const String& chatId, const String& text) {
  bot.sendMessage(chatId, text, "");
}

void runAndReply(const String& chatId, const String& action, long delaySeconds) {
  bool ok;
  reply(chatId, runAction(action, delaySeconds, ok));
}

void handleCommand(const String& chatId, String text) {
  text.trim();

  // Button presses: "do:<action>:<delay seconds>"
  if (text.startsWith("do:")) {
    int separator = text.indexOf(':', 3);
    if (separator < 0) {
      return;
    }
    String action = text.substring(3, separator);
    if (action == "dismiss") {
      reply(chatId, "OK, nothing was done.");
      return;
    }
    runAndReply(chatId, action, text.substring(separator + 1).toInt());
    return;
  }

  String command = text;
  String argument;
  int space = text.indexOf(' ');
  if (space > 0) {
    command = text.substring(0, space);
    argument = text.substring(space + 1);
    argument.trim();
  }
  // Commands may arrive as "/wake@YourBotName" in group chats.
  int at = command.indexOf('@');
  if (at > 0) {
    command = command.substring(0, at);
  }

  if (command == "/wake") {
    runAndReply(chatId, "wake", 0);
  } else if (command == "/status") {
    reply(chatId, formatStatus(probePc()));
  } else if (command == "/shutdown" || command == "/restart") {
    String action = command.substring(1);
    if (argument.length()) {
      runAndReply(chatId, action, argument.toInt() * 60L);
    } else if (action == "shutdown") {
      bot.sendMessageWithInlineKeyboard(chatId, "Shut down the PC? Unsaved work will be lost.", "", SHUTDOWN_KEYBOARD);
    } else {
      bot.sendMessageWithInlineKeyboard(chatId, "Restart the PC? Unsaved work will be lost.", "", RESTART_KEYBOARD);
    }
  } else if (command == "/sleep" || command == "/lock" || command == "/cancel") {
    runAndReply(chatId, command.substring(1), 0);
  } else {
    bot.sendMessageWithInlineKeyboard(chatId, HELP_TEXT, "", MENU_KEYBOARD);
  }
}

void handleMessages(int count) {
  for (int i = 0; i < count; i++) {
    telegramMessage& message = bot.messages[i];

    if (message.type == "callback_query") {
      bot.answerCallbackQuery(message.query_id);
    }

    if (message.chat_id != ALLOWED_CHAT_ID) {
      Serial.println("Ignored message from unauthorized chat " + message.chat_id);
      bot.sendMessage(message.chat_id, "Not authorized.", "");
      continue;
    }

    handleCommand(message.chat_id, message.text);
  }
}

// ---------- Web UI ----------

bool checkWebAuth() {
  if (!server.authenticate(WEB_USERNAME, WEB_PASSWORD)) {
    server.requestAuthentication(BASIC_AUTH, "Remote PC Wake");
    return false;
  }
  return true;
}

void handleWebRoot() {
  if (!checkWebAuth()) return;
  server.sendHeader("Cache-Control", "no-store");
  server.send_P(200, "text/html; charset=utf-8", WEB_UI_HTML);
}

void handleWebState() {
  if (!checkWebAuth()) return;

  PcState shown = server.hasArg("refresh") ? probePc() : pcState;

  JsonDocument doc;
  doc["pc"] = stateName(shown);
  doc["agentConfigured"] = agentEnabled();
  doc["agentError"] = lastAgentError;
  if (shown == PC_ON && !lastAgentJson.isEmpty()) {
    doc["agent"] = serialized(lastAgentJson);
  } else {
    doc["agent"] = nullptr;
  }
  doc["expectation"] = expectationName();
  JsonObject esp = doc["esp"].to<JsonObject>();
  esp["version"] = FIRMWARE_VERSION;
  esp["uptimeSeconds"] = millis() / 1000;
  esp["rssi"] = WiFi.RSSI();

  String out;
  serializeJson(doc, out);
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", out);
}

void handleWebAction() {
  if (!checkWebAuth()) return;

  // The custom header can't be sent cross-site without a CORS preflight, which this
  // server never approves: it blocks other websites from triggering actions.
  if (server.method() != HTTP_POST || server.header("X-Requested-By") != "remote-pc-wake") {
    server.send(400, "application/json", "{\"ok\":false,\"message\":\"Bad request\"}");
    return;
  }

  bool ok;
  String action = server.arg("name");
  String message = runAction(action, server.arg("delay").toInt(), ok);
  if (ok) {
    notify("🌐 Web UI: " + message);
  }

  JsonDocument doc;
  doc["ok"] = ok;
  doc["message"] = message;
  String out;
  serializeJson(doc, out);
  server.send(ok ? 200 : 400, "application/json", out);
}

void startWebServer() {
  if (strlen(WEB_PASSWORD) == 0) {
    Serial.println("Web UI disabled: set WEB_PASSWORD in config.h to enable it.");
    return;
  }
  const char* headers[] = {"X-Requested-By"};
  server.collectHeaders(headers, 1);
  server.on("/", HTTP_GET, handleWebRoot);
  server.on("/api/state", HTTP_GET, handleWebState);
  server.on("/api/action", handleWebAction);
  server.onNotFound([]() { server.send(404, "text/plain", "Not found"); });
  server.begin();

  if (MDNS.begin(DEVICE_HOSTNAME)) {
    MDNS.addService("http", "tcp", 80);
  }
  webEnabled = true;
  Serial.printf("Web UI: http://%s.local or http://%s\n", DEVICE_HOSTNAME, WiFi.localIP().toString().c_str());
}

// ---------- Setup and main loop ----------

// Fixed IP settings from config.h; only used when ESP32_STATIC_IP is set.
IPAddress staticIp, staticGateway, staticSubnet, staticDns;

bool useStaticIp() {
  return strlen(ESP32_STATIC_IP) > 0;
}

void connectWifi() {
  WiFi.persistent(false);  // don't write credentials to flash on every connect
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(DEVICE_HOSTNAME);
  if (useStaticIp()) {
    WiFi.config(staticIp, staticGateway, staticSubnet, staticDns);
  }
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

void haltWithError(const char* message) {
  Serial.println(message);
  while (true) {
    delay(1000);
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  // 80 MHz is the lowest frequency that keeps Wi-Fi working; plenty for this job.
  setCpuFrequencyMhz(CPU_FREQUENCY_MHZ);

  if (!parseMac(PC_MAC, pcMac)) {
    haltWithError("Invalid PC_MAC in config.h. Expected format AA:BB:CC:DD:EE:FF");
  }
  if (!pcIp.fromString(PC_IP_ADDRESS)) {
    haltWithError("Invalid PC_IP_ADDRESS in config.h.");
  }
  if (useStaticIp()) {
    if (!staticIp.fromString(ESP32_STATIC_IP) || !staticGateway.fromString(NETWORK_GATEWAY) ||
        !staticSubnet.fromString(NETWORK_SUBNET)) {
      haltWithError("Invalid ESP32_STATIC_IP, NETWORK_GATEWAY or NETWORK_SUBNET in config.h.");
    }
    // Without a DNS server of its own, use the router, which forwards DNS queries.
    if (!staticDns.fromString(NETWORK_DNS)) {
      staticDns = staticGateway;
    }
  }

  connectWifi();
  secureClient.setCACert(TELEGRAM_CERTIFICATE_ROOT);

  // Discard messages sent while the ESP32 was offline, so an old /wake
  // doesn't turn on the PC unexpectedly after a power outage.
  bot.getUpdates(-1);

  bot.setMyCommands(F("[{\"command\":\"wake\",\"description\":\"Turn on the PC\"},"
                      "{\"command\":\"status\",\"description\":\"Is the PC on? CPU, RAM, disks\"},"
                      "{\"command\":\"shutdown\",\"description\":\"Shut down (optionally in N minutes)\"},"
                      "{\"command\":\"restart\",\"description\":\"Restart (optionally in N minutes)\"},"
                      "{\"command\":\"sleep\",\"description\":\"Put the PC to sleep\"},"
                      "{\"command\":\"lock\",\"description\":\"Lock the PC's screen\"},"
                      "{\"command\":\"cancel\",\"description\":\"Cancel a scheduled shutdown/restart\"},"
                      "{\"command\":\"menu\",\"description\":\"Buttons for all actions\"}]"));

  startWebServer();

  monitorPc();
  lastProbe = millis();

  String status = formatStatus(pcState);
  int firstLineEnd = status.indexOf('\n');
  if (firstLineEnd > 0) {
    status = status.substring(0, firstLineEnd);
  }
  String hello = "🤖 ESP32 online (v" FIRMWARE_VERSION "). " + status;
  if (webEnabled) {
    hello += "\n🌐 Web UI (home network): http://" + String(DEVICE_HOSTNAME) + ".local";
  }
  bot.sendMessageWithInlineKeyboard(ALLOWED_CHAT_ID, hello, "", MENU_KEYBOARD);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWifi();
  }

  if (webEnabled) {
    server.handleClient();
  }

  if (millis() - lastPoll > POLL_INTERVAL_MS) {
    int count = bot.getUpdates(bot.last_message_received + 1);
    while (count) {
      handleMessages(count);
      count = bot.getUpdates(bot.last_message_received + 1);
    }
    lastPoll = millis();
  }

  unsigned long probeInterval = expectationDue() ? FAST_PROBE_INTERVAL_MS : MONITOR_INTERVAL_MS;
  if (millis() - lastProbe > probeInterval) {
    monitorPc();
    lastProbe = millis();
  }

  checkExpectationTimeout();

  delay(IDLE_DELAY_MS);
}
