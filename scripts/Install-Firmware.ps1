<#
.SYNOPSIS
    Installs the WakeDesk firmware on the ESP32 and writes your settings to it (Runbook 03, Step 5).

.DESCRIPTION
    1. Reads your settings from config.h (create it with New-FirmwareConfig.ps1).
    2. Downloads the released firmware from GitHub and checks its SHA-256 (or, with -Build,
       compiles it from this repository with Arduino CLI).
    3. Writes it to the ESP32 with esptool, Espressif's official flashing tool. esptool is
       downloaded once from Espressif's GitHub release and checked against a pinned SHA-256.
    4. Sends your settings to the ESP32 over USB. They're stored on the ESP32, never in the
       firmware file. Flashing erases the stored settings, so they're always sent again.

    No Arduino IDE, compiler or Python is needed unless you use -Build.

.PARAMETER Port
    COM port of the ESP32 (e.g. COM3). Detected automatically if only one board is connected.

.PARAMETER Version
    Firmware release to install, e.g. 1.2.0. Default: the latest release.

.PARAMETER Image
    Flash this local firmware image (a merged .bin) instead of downloading a release. For testing.

.PARAMETER Build
    Compile the firmware from this repository instead of downloading it (needs Install-DevTools.ps1).

.PARAMETER Board
    Arduino board ID for -Build. Default: esp32:esp32:esp32 (ESP32 Dev Module).

.PARAMETER CompileOnly
    Only check that the firmware compiles (needs Install-DevTools.ps1); no ESP32 needed.

.PARAMETER SettingsOnly
    Don't flash; only send the settings in config.h to the ESP32 (e.g. after changing the Wi-Fi).

.PARAMETER Monitor
    Show the ESP32's serial output after installing (Ctrl+C to exit).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -Monitor

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -SettingsOnly

.NOTES
    CHANGES MADE TO THIS PC: downloads, into %LOCALAPPDATA%\WakeDesk\, esptool (once; checked against
      a pinned SHA-256) and the firmware release (checked against the release's SHA256SUMS).
      Writes the firmware and your settings to the ESP32 over USB.
    NETWORK ACCESS: api.github.com and github.com (wakedesk/wakedesk-esp32 releases and
      espressif/esptool releases). With -Build: none.
    UNDO: delete %LOCALAPPDATA%\WakeDesk\.
    Full reference: docs/scripts-reference.md
#>
[CmdletBinding()]
param(
    [string]$Port,
    [string]$Version = 'latest',
    [string]$Image,
    [switch]$Build,
    [string]$Board = 'esp32:esp32:esp32',
    [switch]$CompileOnly,
    [switch]$SettingsOnly,
    [switch]$Monitor
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

if ($SettingsOnly -and ($Build -or $CompileOnly -or $Image)) {
    throw '-SettingsOnly cannot be combined with -Build, -CompileOnly or -Image.'
}
if ($Image -and $Build) {
    throw '-Image cannot be combined with -Build.'
}
if ($Image -and -not (Test-Path $Image)) {
    throw "Firmware image not found: $Image"
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SketchDir = Join-Path $RepoRoot 'firmware\remote-pc-wake'
$ConfigPath = Join-Path $SketchDir 'config.h'
$CacheDir = Join-Path $env:LOCALAPPDATA 'WakeDesk'
$ReleasesApi = 'https://api.github.com/repos/wakedesk/wakedesk-esp32/releases'

# esptool, pinned: update the version and hash together, from the release page on GitHub.
$EsptoolVersion = 'v5.5.0'
$EsptoolUrl = "https://github.com/espressif/esptool/releases/download/$EsptoolVersion/esptool-$EsptoolVersion-windows-amd64.zip"
$EsptoolSha256 = 'e7142a6b6714173b8337e6044984198344c5da31341b333f3d89a59ed8d1ea57'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-Esptool {
    $dir = Join-Path $CacheDir "tools\esptool-$EsptoolVersion"
    $exe = Get-ChildItem -Path $dir -Recurse -Filter 'esptool.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { return $exe.FullName }

    Write-Info "Downloading esptool $EsptoolVersion from Espressif's GitHub release..."
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $zip = Join-Path $dir 'esptool.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $EsptoolUrl -OutFile $zip
    if ((Get-Sha256 $zip) -ne $EsptoolSha256) {
        Remove-Item -Force $zip
        throw 'The downloaded esptool does not match the expected SHA-256. Nothing was run.'
    }
    Expand-Archive -Force -Path $zip -DestinationPath $dir
    Remove-Item -Force $zip
    $exe = Get-ChildItem -Path $dir -Recurse -Filter 'esptool.exe' | Select-Object -First 1
    if (-not $exe) { throw 'esptool.exe not found in the downloaded archive.' }
    Write-Ok 'esptool downloaded and verified.'
    return $exe.FullName
}

function Get-ReleasedFirmware([string]$Wanted) {
    $url = if ($Wanted -eq 'latest') { "$ReleasesApi/latest" } else { "$ReleasesApi/tags/v$($Wanted.TrimStart('v'))" }
    $release = Invoke-RestMethod -UseBasicParsing -Uri $url -Headers @{ Accept = 'application/vnd.github+json' }
    $tag = $release.tag_name
    $binAsset = $release.assets | Where-Object { $_.name -match '^wakedesk-esp32-.*\.bin$' } | Select-Object -First 1
    $sumsAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if (-not $binAsset -or -not $sumsAsset) {
        throw "Release $tag has no firmware image yet. Try again in a few minutes, or use -Build."
    }

    $dir = Join-Path $CacheDir "firmware\$tag"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bin = Join-Path $dir $binAsset.name
    $sums = Join-Path $dir 'SHA256SUMS'
    Write-Info "Downloading firmware $tag..."
    Invoke-WebRequest -UseBasicParsing -Uri $sumsAsset.browser_download_url -OutFile $sums
    Invoke-WebRequest -UseBasicParsing -Uri $binAsset.browser_download_url -OutFile $bin

    $expected = Get-Content $sums | Where-Object { $_ -match "^([0-9a-f]{64})\s+\*?$([regex]::Escape($binAsset.name))$" } |
        ForEach-Object { $Matches[1] } | Select-Object -First 1
    if (-not $expected -or (Get-Sha256 $bin) -ne $expected) {
        Remove-Item -Force $bin
        throw "The firmware image of $tag does not match its SHA-256. Nothing was flashed."
    }
    Write-Ok "Firmware $tag downloaded and verified."
    return $bin
}

function Invoke-FirmwareBuild([string]$Fqbn) {
    $cli = Find-ArduinoCli
    if (-not $cli) { throw 'arduino-cli not found. Run scripts\Install-DevTools.ps1 first, or install without -Build.' }
    $out = Join-Path $CacheDir 'build'
    Write-Info "Compiling for $Fqbn..."
    & $cli compile --fqbn $Fqbn --output-dir $out $SketchDir
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed. See the errors above (Runbook 02, Troubleshooting).' }
    $bin = Get-ChildItem -Path $out -Filter '*.merged.bin' | Select-Object -First 1
    if (-not $bin) { throw 'The build produced no merged image.' }
    Write-Ok 'Firmware compiled.'
    return $bin.FullName
}

# Settings sent to the ESP32: every setting of config.h, so the ESP32 mirrors the file exactly.
function Get-FirmwareConfiguration {
    if (-not (Test-Path $ConfigPath)) {
        throw 'config.h not found. Create it with scripts\New-FirmwareConfig.ps1 first.'
    }
    $text = Get-Content -Raw -Encoding UTF8 $ConfigPath
    $settings = [ordered]@{
        wifi_ssid     = Get-Define $text 'WIFI_SSID'
        wifi_password = Get-Define $text 'WIFI_PASSWORD'
        bot_token     = Get-Define $text 'BOT_TOKEN'
        chat_id       = Get-Define $text 'ALLOWED_CHAT_ID'
        pc_mac        = Get-Define $text 'PC_MAC'
        pc_ip         = Get-Define $text 'PC_IP_ADDRESS'
        pc_check_port = Get-DefineNumber $text 'PC_CHECK_PORT' 3389
        agent_token   = Get-Define $text 'AGENT_TOKEN'
        agent_port    = Get-DefineNumber $text 'AGENT_PORT' 8765
        web_user      = Get-Define $text 'WEB_USERNAME'
        web_password  = Get-Define $text 'WEB_PASSWORD'
        hostname      = Get-Define $text 'DEVICE_HOSTNAME'
        static_ip     = Get-Define $text 'ESP32_STATIC_IP'
        gateway       = Get-Define $text 'NETWORK_GATEWAY'
        subnet        = Get-Define $text 'NETWORK_SUBNET'
        dns           = Get-Define $text 'NETWORK_DNS'
    }
    if (-not $settings.web_user) { $settings.web_user = 'admin' }
    if (-not $settings.hostname) { $settings.hostname = 'remote-pc-wake' }
    if (-not $settings.subnet) { $settings.subnet = '255.255.255.0' }
    foreach ($required in 'wifi_ssid', 'wifi_password', 'bot_token', 'chat_id', 'pc_mac', 'pc_ip') {
        if (-not $settings[$required]) { throw "config.h has no $required. Run scripts\New-FirmwareConfig.ps1." }
    }
    return $settings
}

# Reads serial lines until one matches, or the timeout passes.
function Wait-SerialLine($Serial, [string]$Pattern, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $line = $Serial.ReadLine().Trim()
        }
        catch [System.TimeoutException] {
            continue
        }
        Write-Verbose "ESP32: $line"
        if ($line -match $Pattern) { return $line }
    }
    return $null
}

# Restarts the ESP32 through the USB adapter's RTS line (the EN pin on most boards).
function Invoke-Esp32Reset($Serial) {
    $Serial.DtrEnable = $false
    $Serial.RtsEnable = $true
    Start-Sleep -Milliseconds 150
    $Serial.RtsEnable = $false
}

function Send-Esp32Configuration([string]$ComPort, $Settings) {
    $serial = New-Object System.IO.Ports.SerialPort $ComPort, 115200
    $serial.ReadTimeout = 500
    $serial.NewLine = "`n"
    $serial.Open()
    try {
        Invoke-Esp32Reset $serial
        if (-not (Wait-SerialLine $serial '^WAKEDESK READY ' 15)) {
            throw 'The ESP32 did not answer. Check that it runs WakeDesk firmware 1.2.0 or later and that no other program uses the port.'
        }

        $command = ConvertTo-Json -Compress -InputObject ([ordered]@{ cmd = 'provision'; settings = $Settings })
        $serial.WriteLine($command)
        $reply = Wait-SerialLine $serial '^WAKEDESK \{' 10
        if (-not $reply) { throw 'The ESP32 did not confirm the settings.' }
        $result = $reply.Substring(9) | ConvertFrom-Json
        if (-not $result.ok) { throw "The ESP32 rejected the settings: $($result.error)" }
        Write-Ok 'Settings stored on the ESP32. Restarting it...'

        if (-not (Wait-SerialLine $serial '^WAKEDESK READY .*"provisioned":true' 15)) {
            throw 'The ESP32 did not restart with the new settings.'
        }
        $connected = Wait-SerialLine $serial '^Connected\. IP: ' 40
        if ($connected) {
            Write-Ok "ESP32 connected to Wi-Fi: $($connected.Substring(15))"
        }
        else {
            Write-Warn 'The ESP32 has not connected to Wi-Fi yet. Check the Wi-Fi name and password (2.4 GHz), or use -Monitor.'
        }
    }
    finally {
        $serial.Close()
    }
}

function Show-SerialMonitor([string]$ComPort) {
    Write-Step "Serial monitor on $ComPort (Ctrl+C to exit)"
    $serial = New-Object System.IO.Ports.SerialPort $ComPort, 115200
    $serial.ReadTimeout = 500
    $serial.Open()
    try {
        while ($true) {
            try { Write-Host $serial.ReadLine() } catch [System.TimeoutException] { Write-Verbose 'waiting for output' }
        }
    }
    finally {
        $serial.Close()
    }
}

# ---------------------------------------------------------------------------
if ($CompileOnly) {
    Write-Step 'Compiling'
    Invoke-FirmwareBuild $Board | Out-Null
    return
}

Write-Step 'Reading your settings'
$settings = Get-FirmwareConfiguration
Write-Ok "Settings for Wi-Fi '$($settings.wifi_ssid)' and PC $($settings.pc_ip) ($($settings.pc_mac))"

Write-Step 'Finding the ESP32'
if (-not $Port) {
    $boards = @(Get-Esp32SerialPort | Where-Object { $_.Port -and $_.Status -eq 'OK' })
    if ($boards.Count -eq 0) {
        throw 'No ESP32 detected. Connect it with a USB data cable (run Install-DevTools.ps1 to check the driver), or pass -Port COMx.'
    }
    if ($boards.Count -gt 1) {
        throw "Several boards detected ($(($boards.Port) -join ', ')). Pick one with -Port."
    }
    $Port = $boards[0].Port
}
Write-Ok "Using $Port"

if (-not $SettingsOnly) {
    Write-Step 'Getting the firmware'
    $image = if ($Image) { (Resolve-Path $Image).Path } elseif ($Build) { Invoke-FirmwareBuild $Board } else { Get-ReleasedFirmware $Version }

    Write-Step 'Flashing'
    $esptool = Get-Esptool
    & $esptool --chip esp32 --port $Port --baud 460800 write-flash 0x0 $image
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Flashing failed. If it got stuck on "Connecting...", hold the BOOT button on the board and run this script again.'
        Write-Warn 'If the port is busy, close the Arduino IDE Serial Monitor or any other program using it.'
        throw 'Flashing failed.'
    }
    Write-Ok 'Firmware written.'
}

Write-Step 'Sending your settings to the ESP32'
Send-Esp32Configuration $Port $settings
Write-Ok 'Done. The ESP32 sends "ESP32 online" to Telegram in a few seconds.'

if ($Monitor) {
    Show-SerialMonitor $Port
}
