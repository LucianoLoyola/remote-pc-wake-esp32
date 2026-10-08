// Runtime settings.
//
// Released firmware images contain no personal data: the settings live in the ESP32's
// non-volatile storage (NVS) and are written over USB by scripts/Install-Firmware.ps1 (or the
// WakeDesk app). People who build the firmware themselves can still use config.h: every
// setting not stored in NVS falls back to its config.h value.
//
// USB provisioning protocol (115200 baud, one JSON object per line):
//   on boot the firmware prints   WAKEDESK READY {"firmware":"x.y.z","provisioned":true}
//   and listens for a few seconds (forever while it isn't provisioned). Commands:
//     {"cmd":"info"}                          -> current settings, without secrets
//     {"cmd":"provision","settings":{...}}    -> validates, stores and restarts
//     {"cmd":"reset"}                         -> erases the stored settings and restarts
//   Replies are one line: WAKEDESK {"ok":true,...} or WAKEDESK {"ok":false,"error":"..."}

#pragma once

#include <Preferences.h>
#include <ArduinoJson.h>

struct Settings {
  String wifiSsid;
  String wifiPassword;
  String botToken;
  String chatId;
  String pcMac;
  String pcIp;
  uint16_t pcCheckPort;
  String agentToken;
  uint16_t agentPort;
  String webUser;
  String webPassword;
  String hostname;
  String staticIp;
  String gateway;
  String subnet;
  String dns;
};

Settings settings;

const char* const SETTINGS_NAMESPACE = "wakedesk";
const unsigned long PROVISIONING_WINDOW_MS = 3000;

// String settings, their NVS key (also the JSON key) and whether they're secret.
struct StringField {
  const char* key;
  String Settings::*member;
  bool secret;
};

const StringField STRING_FIELDS[] = {
    {"wifi_ssid", &Settings::wifiSsid, false},
    {"wifi_password", &Settings::wifiPassword, true},
    {"bot_token", &Settings::botToken, true},
    {"chat_id", &Settings::chatId, false},
    {"pc_mac", &Settings::pcMac, false},
    {"pc_ip", &Settings::pcIp, false},
    {"agent_token", &Settings::agentToken, true},
    {"web_user", &Settings::webUser, false},
    {"web_password", &Settings::webPassword, true},
    {"hostname", &Settings::hostname, false},
    {"static_ip", &Settings::staticIp, false},
    {"gateway", &Settings::gateway, false},
    {"subnet", &Settings::subnet, false},
    {"dns", &Settings::dns, false},
};

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

void loadSettings() {
  // Defaults from config.h (empty in released images).
  settings.wifiSsid = WIFI_SSID;
  settings.wifiPassword = WIFI_PASSWORD;
  settings.botToken = BOT_TOKEN;
  settings.chatId = ALLOWED_CHAT_ID;
  settings.pcMac = PC_MAC;
  settings.pcIp = PC_IP_ADDRESS;
  settings.pcCheckPort = PC_CHECK_PORT;
  settings.agentToken = AGENT_TOKEN;
  settings.agentPort = AGENT_PORT;
  settings.webUser = WEB_USERNAME;
  settings.webPassword = WEB_PASSWORD;
  settings.hostname = DEVICE_HOSTNAME;
  settings.staticIp = ESP32_STATIC_IP;
  settings.gateway = NETWORK_GATEWAY;
  settings.subnet = NETWORK_SUBNET;
  settings.dns = NETWORK_DNS;

  Preferences prefs;
  if (!prefs.begin(SETTINGS_NAMESPACE, true)) {
    return;  // nothing stored yet
  }
  for (const StringField& field : STRING_FIELDS) {
    if (prefs.isKey(field.key)) {
      settings.*field.member = prefs.getString(field.key);
    }
  }
  if (prefs.isKey("pc_check_port")) settings.pcCheckPort = prefs.getUShort("pc_check_port");
  if (prefs.isKey("agent_port")) settings.agentPort = prefs.getUShort("agent_port");
  prefs.end();
}

bool isProvisioned() {
  return !settings.wifiSsid.isEmpty() && !settings.botToken.isEmpty() && !settings.chatId.isEmpty() &&
         !settings.pcMac.isEmpty() && !settings.pcIp.isEmpty();
}

void provisioningReply(JsonDocument& doc) {
  String out;
  serializeJson(doc, out);
  Serial.print("WAKEDESK ");
  Serial.println(out);
}

void provisioningError(const String& message) {
  JsonDocument doc;
  doc["ok"] = false;
  doc["error"] = message;
  provisioningReply(doc);
}

// Checks the values that the firmware parses at startup, so bad settings are rejected now
// instead of leaving a device that can't boot.
String validateProvisioning(JsonObject in) {
  uint8_t mac[6];
  IPAddress ip;
  if (in["pc_mac"].is<const char*>() && !parseMac(in["pc_mac"], mac)) return "pc_mac must look like AA:BB:CC:DD:EE:FF";
  for (const char* key : {"pc_ip", "gateway", "subnet", "dns", "static_ip"}) {
    const char* value = in[key] | "";
    if (in[key].is<const char*>() && strlen(value) > 0 && !ip.fromString(value)) return String(key) + " is not a valid IPv4 address";
  }
  for (const char* key : {"pc_check_port", "agent_port"}) {
    if (!in[key].isNull() && !(in[key].is<int>() && in[key].as<int>() > 0 && in[key].as<int>() <= 65535)) {
      return String(key) + " must be a port number";
    }
  }
  if (!(in["static_ip"] | String()).isEmpty() && (in["gateway"] | String()).isEmpty() && settings.gateway.isEmpty()) {
    return "static_ip needs a gateway";
  }
  return "";
}

void handleProvisioningCommand(const String& line) {
  JsonDocument doc;
  if (deserializeJson(doc, line)) {
    provisioningError("invalid JSON");
    return;
  }
  String cmd = doc["cmd"] | "";

  if (cmd == "info") {
    JsonDocument reply;
    reply["ok"] = true;
    reply["firmware"] = FIRMWARE_VERSION;
    reply["provisioned"] = isProvisioned();
    for (const StringField& field : STRING_FIELDS) {
      if (field.secret) {
        reply[field.key] = !(settings.*field.member).isEmpty();  // only whether it's set
      } else {
        reply[field.key] = settings.*field.member;
      }
    }
    reply["pc_check_port"] = settings.pcCheckPort;
    reply["agent_port"] = settings.agentPort;
    provisioningReply(reply);
    return;
  }

  if (cmd == "provision") {
    JsonObject in = doc["settings"].as<JsonObject>();
    if (in.isNull()) {
      provisioningError("missing settings");
      return;
    }
    String problem = validateProvisioning(in);
    if (!problem.isEmpty()) {
      provisioningError(problem);
      return;
    }
    Preferences prefs;
    if (!prefs.begin(SETTINGS_NAMESPACE, false)) {
      provisioningError("cannot open storage");
      return;
    }
    for (const StringField& field : STRING_FIELDS) {
      if (in[field.key].is<const char*>()) prefs.putString(field.key, in[field.key].as<const char*>());
    }
    if (in["pc_check_port"].is<int>()) prefs.putUShort("pc_check_port", in["pc_check_port"].as<int>());
    if (in["agent_port"].is<int>()) prefs.putUShort("agent_port", in["agent_port"].as<int>());
    prefs.end();

    JsonDocument reply;
    reply["ok"] = true;
    reply["restarting"] = true;
    provisioningReply(reply);
    Serial.flush();
    delay(200);
    ESP.restart();
  }

  if (cmd == "reset") {
    Preferences prefs;
    if (prefs.begin(SETTINGS_NAMESPACE, false)) {
      prefs.clear();
      prefs.end();
    }
    JsonDocument reply;
    reply["ok"] = true;
    reply["restarting"] = true;
    provisioningReply(reply);
    Serial.flush();
    delay(200);
    ESP.restart();
  }

  provisioningError("unknown command");
}

void announceProvisioning() {
  JsonDocument doc;
  doc["firmware"] = FIRMWARE_VERSION;
  doc["provisioned"] = isProvisioned();
  String out;
  serializeJson(doc, out);
  Serial.print("WAKEDESK READY ");
  Serial.println(out);
}

// Listens for USB commands for a few seconds, or until provisioned if there are no settings.
void runProvisioningWindow() {
  announceProvisioning();
  unsigned long start = millis();
  unsigned long lastAnnounce = start;
  String line;
  while (!isProvisioned() || millis() - start < PROVISIONING_WINDOW_MS) {
    while (Serial.available()) {
      char c = Serial.read();
      if (c == '\n' || c == '\r') {
        line.trim();
        if (line.startsWith("{")) {
          handleProvisioningCommand(line);
          start = millis();  // keep listening while a tool is talking to us
        }
        line = "";
      } else if (line.length() < 2048) {
        line += c;
      }
    }
    if (!isProvisioned() && millis() - lastAnnounce > 5000) {
      announceProvisioning();
      lastAnnounce = millis();
    }
    delay(10);
  }
}
