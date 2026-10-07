<#
.SYNOPSIS
    Creates or updates the firmware's config.h (Runbook 03, Step 4).

.DESCRIPTION
    Fills in config.h, detecting as much as possible:
      - PC MAC and IP: from this PC's Ethernet adapter (run it on the target PC)
      - Agent token: from the installed PC agent (needs Administrator)
      - Telegram ID: you send a message to your bot and the script reads your ID
    and asks for the rest (Wi-Fi, bot token, web UI password).

    If config.h already exists, its values are kept unless you pass new ones,
    so you can run it again to change a single setting.

.PARAMETER WifiSsid
    Wi-Fi network name (2.4 GHz).
.PARAMETER WifiPassword
    Wi-Fi password (SecureString). Asked for securely when config.h has none
    or when -WifiSsid changes the network.
.PARAMETER ChangeWifiPassword
    Ask for a new Wi-Fi password even if the network name didn't change.
.PARAMETER BotToken
    Telegram bot token from @BotFather.
.PARAMETER ChatId
    Your Telegram user ID. Detected automatically if omitted.
.PARAMETER PcMac
    MAC of the target PC. Detected automatically when run on the target PC.
.PARAMETER PcIp
    LAN IP of the target PC. Detected automatically when run on the target PC.
.PARAMETER AgentToken
    PC agent token. Read from the installed agent if omitted (Administrator).
.PARAMETER WebPassword
    Web UI password (SecureString). Asked for securely the first time.
.PARAMETER ChangeWebPassword
    Ask for a new web UI password even if one is already set.
.PARAMETER DisableWebUi
    Remove the web UI password, which disables the web UI.
.PARAMETER Esp32StaticIp
    Fixed IP address for the ESP32, for routers that can't reserve one, or "auto" to pick
    a free one near the top of your network. The gateway and subnet are taken from this
    PC's network settings.
.PARAMETER Esp32UseDhcp
    Remove the ESP32's fixed IP address: it gets one from the router again.
.PARAMETER OutputPath
    Where to write config.h. Default: firmware\remote-pc-wake\config.h

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1 -WifiSsid "NewNetwork"
    Changes the Wi-Fi network; the script asks for its password.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1 -Esp32StaticIp auto
    Gives the ESP32 a fixed IP address, choosing a free one automatically.

.NOTES
    CHANGES MADE TO THIS PC: writes only firmware\remote-pc-wake\config.h in the repository
      (git-ignored; contains your secrets in plain text because the firmware needs them).
    NETWORK ACCESS: api.telegram.org (getMe, getUpdates), only to detect your Telegram ID.
      It never sends messages. With -Esp32StaticIp, pings addresses on the local network
      (and reads the ARP table) to check or find a free one.
    UNDO: delete config.h.
    Full reference: docs/scripts-reference.md
#>
[CmdletBinding()]
param(
    [string]$WifiSsid,
    [SecureString]$WifiPassword,
    [switch]$ChangeWifiPassword,
    [string]$BotToken,
    [string]$ChatId,
    [string]$PcMac,
    [string]$PcIp,
    [string]$AgentToken,
    [SecureString]$WebPassword,
    [switch]$ChangeWebPassword,
    [switch]$DisableWebUi,
    [string]$Esp32StaticIp,
    [switch]$Esp32UseDhcp,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SketchDir = Join-Path $RepoRoot 'firmware\remote-pc-wake'
$ExamplePath = Join-Path $SketchDir 'config.example.h'
if (-not $OutputPath) { $OutputPath = Join-Path $SketchDir 'config.h' }
$AgentConfigPath = Join-Path $env:ProgramData 'RemotePcWake\config.json'
$ChatDetectTimeoutSeconds = 120

# Values in config.example.h that mean "not configured yet"
$Placeholders = @('YOUR_WIFI_NAME', 'YOUR_WIFI_PASSWORD', '123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ', '123456789', 'AA:BB:CC:DD:EE:FF', '')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-Define([string]$Text, [string]$Key) {
    if ($Text -match "(?m)^#define\s+$Key\s+`"((?:[^`"\\]|\\.)*)`"") {
        return $Matches[1] -replace '\\(.)', '$1'
    }
    return ''
}

function Edit-Define([string]$Text, [string]$Key, [string]$Value) {
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    $pattern = "(?m)^(#define\s+$Key\s+)`"(?:[^`"\\]|\\.)*`""
    if ($Text -notmatch $pattern) {
        # config.h created by an older version: add the setting at the end
        return $Text.TrimEnd() + "`n#define $Key `"$escaped`"`n"
    }
    return [regex]::Replace($Text, $pattern, { param($m) $m.Groups[1].Value + '"' + $escaped + '"' })
}

function Test-Configured([string]$Value) {
    return $Placeholders -notcontains $Value
}

# config.h stores secrets in plain text, so they have to be decoded at the end.
function ConvertTo-PlainText([SecureString]$Secure) {
    if (-not $Secure) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Read-Secret([string]$Prompt) {
    return ConvertTo-PlainText (Read-Host -Prompt $Prompt -AsSecureString)
}

# Parameter > detected > existing value > prompt
function Resolve-Setting([string]$Label, [string]$Given, [string]$Detected, [string]$Current, [switch]$Secret, [string]$Suggestion) {
    if ($Given) { return $Given }
    if ($Detected) { return $Detected }
    if (Test-Configured $Current) { return $Current }
    $prompt = if ($Suggestion) { "$Label [$Suggestion]" } else { $Label }
    $value = if ($Secret) { Read-Secret $prompt } else { Read-Host -Prompt $prompt }
    if (-not $value) { $value = $Suggestion }
    if (-not $value) { throw "$Label is required." }
    return $value
}

function Get-CurrentWifiSsid {
    $ErrorActionPreference = 'Continue'
    $line = & netsh.exe wlan show interfaces 2>$null | Where-Object { $_ -match '^\s+SSID\s+:\s+(.+)$' } | Select-Object -First 1
    if ($line -and $line -match '^\s+SSID\s+:\s+(.+)$') { return $Matches[1].Trim() }
    return $null
}

function Get-TelegramChatId([string]$Token) {
    $api = "https://api.telegram.org/bot$Token"
    try {
        $bot = (Invoke-RestMethod "$api/getMe").result
    }
    catch {
        throw 'The bot token was rejected by Telegram. Copy it again from @BotFather.'
    }
    Write-Ok "Bot found: @$($bot.username)"
    Write-Info "Open Telegram, go to @$($bot.username) and send it any message (press Start if it's new)."
    Write-Info "Waiting up to $ChatDetectTimeoutSeconds seconds..."

    $deadline = (Get-Date).AddSeconds($ChatDetectTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $updates = (Invoke-RestMethod "$api/getUpdates").result
        $message = $updates | ForEach-Object { $_.message } |
            Where-Object { $_ -and $_.chat.type -eq 'private' } | Select-Object -Last 1
        if ($message) {
            Write-Ok "Message received from $($message.from.first_name) (ID $($message.chat.id))."
            return [string]$message.chat.id
        }
        Start-Sleep -Seconds 3
    }
    throw 'No message received. Run the script again, or pass -ChatId (get it from @userinfobot).'
}

# ---------------------------------------------------------------------------
$templatePath = if (Test-Path $OutputPath) { $OutputPath } else { $ExamplePath }
$text = Get-Content -Raw -Encoding UTF8 $templatePath
if (Test-Path $OutputPath) {
    Write-Step "Updating existing $OutputPath"
}
else {
    Write-Step "Creating $OutputPath"
}

# ---------------------------------------------------------------------------
Write-Step 'Target PC'
$detectedMac = $null
$detectedIp = $null
if (-not ($PcMac -and $PcIp)) {
    try {
        $adapter = Get-WakeAdapter
        $detectedMac = Format-Mac $adapter.MacAddress
        $detectedIp = Get-AdapterIPv4 $adapter
        Write-Ok "Detected this PC's Ethernet adapter: $detectedMac / $detectedIp"
        Write-Info 'If this is NOT the PC you want to wake, run again with -PcMac and -PcIp.'
    }
    catch {
        Write-Warn 'No Ethernet adapter detected on this PC; enter the target PC values.'
    }
}
$mac = Resolve-Setting 'PC MAC address (AA:BB:CC:DD:EE:FF)' $PcMac $detectedMac (Get-Define $text 'PC_MAC')
if ($mac -notmatch '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$') { throw "Invalid MAC address: $mac" }
$ip = Resolve-Setting 'PC IP address' $PcIp $detectedIp (Get-Define $text 'PC_IP_ADDRESS')
$parsedIp = $null
if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) { throw "Invalid IP address: $ip" }

# ---------------------------------------------------------------------------
Write-Step 'Wi-Fi (2.4 GHz)'
$currentSsid = Get-Define $text 'WIFI_SSID'
$ssid = Resolve-Setting 'Wi-Fi name' $WifiSsid $null $currentSsid -Suggestion (Get-CurrentWifiSsid)
# A different network needs its own password, so don't reuse the stored one.
$currentWifiPass = if ($ssid -eq $currentSsid -and -not $ChangeWifiPassword) { Get-Define $text 'WIFI_PASSWORD' } else { '' }
$wifiPass = Resolve-Setting 'Wi-Fi password' (ConvertTo-PlainText $WifiPassword) $null $currentWifiPass -Secret
Write-Ok "Wi-Fi: $ssid"

# ---------------------------------------------------------------------------
Write-Step 'ESP32 address'
$espIp = Get-Define $text 'ESP32_STATIC_IP'
$espGateway = Get-Define $text 'NETWORK_GATEWAY'
$espSubnet = Get-Define $text 'NETWORK_SUBNET'
if (-not $espSubnet) { $espSubnet = '255.255.255.0' }

if ($Esp32UseDhcp) {
    $espIp = ''
    $espGateway = ''
}
elseif ($Esp32StaticIp) {
    $lan = $null
    try { $lan = Get-LanInterface (Get-WakeAdapter) } catch { Write-Verbose $_.Exception.Message }
    if (-not $lan) {
        throw "Could not read this PC's network settings. Run this script on the target PC, connected to the router."
    }
    $espGateway = $lan.Gateway
    $espSubnet = ConvertTo-SubnetMask $lan.PrefixLength

    if ($Esp32StaticIp -eq 'auto') {
        Write-Info 'Looking for a free address near the top of your network...'
        $espIp = Find-FreeIPv4Address $lan.Gateway $lan.PrefixLength @($ip)
        if (-not $espIp) { throw 'No free address found near the top of the network. Pass one with -Esp32StaticIp.' }
    }
    else {
        if (-not (Test-IPv4Address $Esp32StaticIp)) { throw "Invalid ESP32 IP address: $Esp32StaticIp" }
        if (-not (Test-SameSubnet $Esp32StaticIp $lan.Gateway $lan.PrefixLength)) {
            throw "$Esp32StaticIp is not in your network ($($lan.Gateway)/$($lan.PrefixLength))."
        }
        if ($Esp32StaticIp -eq $ip) { throw 'The ESP32 and the PC cannot use the same IP address.' }
        if ($Esp32StaticIp -eq $lan.Gateway) { throw "$Esp32StaticIp is the router's own address." }
        $espIp = $Esp32StaticIp
        if (Test-IPv4InUse $espIp) {
            Write-Warn "$espIp is in use on the network. That's fine if it's the ESP32 itself; otherwise choose another address."
        }
    }
}
if ($espIp) {
    Write-Ok "Fixed IP: $espIp (gateway $espGateway, subnet $espSubnet)"
}
else {
    Write-Ok 'Automatic: the router assigns the address (DHCP).'
}

# ---------------------------------------------------------------------------
Write-Step 'Telegram'
$token = Resolve-Setting 'Bot token (from @BotFather)' $BotToken $null (Get-Define $text 'BOT_TOKEN') -Secret
$currentChat = Get-Define $text 'ALLOWED_CHAT_ID'
$chat = if ($ChatId) { $ChatId } elseif (Test-Configured $currentChat) { $currentChat } else { Get-TelegramChatId $token }
if ($chat -notmatch '^-?\d+$') { throw "Invalid Telegram ID: $chat" }
Write-Ok "Allowed Telegram ID: $chat"

# ---------------------------------------------------------------------------
Write-Step 'PC agent'
$agent = $AgentToken
if (-not $agent -and (Test-Path (Split-Path $AgentConfigPath))) {
    try {
        $agent = (Get-Content -Raw $AgentConfigPath -ErrorAction Stop | ConvertFrom-Json).Token
        Write-Ok 'Token read from the installed agent.'
    }
    catch {
        Write-Warn 'The agent is installed but its token is only readable as Administrator. Run this script as Administrator, or pass -AgentToken.'
    }
}
if (-not $agent) { $agent = Get-Define $text 'AGENT_TOKEN' }
if ($agent) {
    Write-Ok 'Agent features enabled.'
}
else {
    Write-Warn 'No agent token: shutdown/restart/sleep/lock and stats stay disabled (install the agent with Install-Agent.ps1).'
}

# ---------------------------------------------------------------------------
Write-Step 'Web UI'
$web = ConvertTo-PlainText $WebPassword
if ($DisableWebUi) {
    $web = ''
}
elseif (-not $web) {
    if (-not $ChangeWebPassword) { $web = Get-Define $text 'WEB_PASSWORD' }
    if (-not $web) { $web = Read-Secret 'Web UI password (leave empty to disable the web UI)' }
}
if ($web) {
    $webUser = Get-Define $text 'WEB_USERNAME'
    if (-not $webUser) { $webUser = 'admin' }
    $webHost = Get-Define $text 'DEVICE_HOSTNAME'
    if (-not $webHost) { $webHost = 'remote-pc-wake' }
    Write-Ok "Web UI enabled: http://$webHost.local (home network), user '$webUser', the password you chose."
}
else {
    Write-Warn 'Web UI disabled (no password).'
}

# ---------------------------------------------------------------------------
$text = Edit-Define $text 'WIFI_SSID' $ssid
$text = Edit-Define $text 'WIFI_PASSWORD' $wifiPass
$text = Edit-Define $text 'BOT_TOKEN' $token
$text = Edit-Define $text 'ALLOWED_CHAT_ID' $chat
$text = Edit-Define $text 'PC_MAC' (Format-Mac $mac)
$text = Edit-Define $text 'PC_IP_ADDRESS' $ip
$text = Edit-Define $text 'ESP32_STATIC_IP' $espIp
$text = Edit-Define $text 'NETWORK_GATEWAY' $espGateway
$text = Edit-Define $text 'NETWORK_SUBNET' $espSubnet
$text = Edit-Define $text 'AGENT_TOKEN' $agent
$text = Edit-Define $text 'WEB_PASSWORD' $web

[IO.File]::WriteAllText($OutputPath, $text, (New-Object Text.UTF8Encoding $false))

Write-Step 'Done'
Write-Ok "Saved $OutputPath (git-ignored: it contains secrets)."
Write-Info 'Next: build and upload with scripts\Install-Firmware.ps1'
