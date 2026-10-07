<#
.SYNOPSIS
    Builds the firmware and uploads it to the ESP32 (Runbook 03, Step 5).

.DESCRIPTION
    1. Checks that config.h exists (create it with New-FirmwareConfig.ps1).
    2. Compiles the firmware with Arduino CLI.
    3. Finds the ESP32's COM port (or uses -Port) and uploads the firmware.
    4. Optionally opens the serial monitor to watch it boot.

    Requires the tools from Install-DevTools.ps1.

.PARAMETER Port
    COM port of the ESP32 (e.g. COM3). Detected automatically if only one board is connected.

.PARAMETER Board
    Arduino board ID. Default: esp32:esp32:esp32 (ESP32 Dev Module).
    Examples: esp32:esp32:esp32s3, esp32:esp32:esp32c3.

.PARAMETER CompileOnly
    Only compile; don't upload.

.PARAMETER Monitor
    Open the serial monitor after uploading (Ctrl+C to exit).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -Monitor
#>
[CmdletBinding()]
param(
    [string]$Port,
    [string]$Board = 'esp32:esp32:esp32',
    [switch]$CompileOnly,
    [switch]$Monitor
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

$SketchDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'firmware\remote-pc-wake'

$cli = Find-ArduinoCli
if (-not $cli) {
    throw 'arduino-cli not found. Run scripts\Install-DevTools.ps1 first.'
}
if (-not (Test-Path (Join-Path $SketchDir 'config.h'))) {
    throw 'config.h not found. Create it with scripts\New-FirmwareConfig.ps1 first.'
}

# ---------------------------------------------------------------------------
Write-Step "Compiling for $Board"
& $cli compile --fqbn $Board $SketchDir
if ($LASTEXITCODE -ne 0) {
    throw 'Compilation failed. See the errors above (Runbook 02, Troubleshooting).'
}
Write-Ok 'Firmware compiled.'

if ($CompileOnly) { return }

# ---------------------------------------------------------------------------
Write-Step 'Finding the ESP32'
if (-not $Port) {
    $boards = @(Get-Esp32SerialPorts | Where-Object { $_.Port -and $_.Status -eq 'OK' })
    if ($boards.Count -eq 0) {
        throw 'No ESP32 detected. Connect it with a USB data cable (run Install-DevTools.ps1 to check the driver), or pass -Port COMx.'
    }
    if ($boards.Count -gt 1) {
        throw "Several boards detected ($(($boards.Port) -join ', ')). Pick one with -Port."
    }
    $Port = $boards[0].Port
}
Write-Ok "Using $Port"

# ---------------------------------------------------------------------------
Write-Step 'Uploading'
& $cli upload --fqbn $Board --port $Port $SketchDir
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Upload failed. If it got stuck on "Connecting...", hold the BOOT button on the board and run this script again.'
    Write-Warn 'If the port is busy, close the Arduino IDE Serial Monitor or any other program using it.'
    throw 'Upload failed.'
}
Write-Ok 'Firmware uploaded. The ESP32 restarts and sends "ESP32 online" to Telegram.'

if ($Monitor) {
    Write-Step 'Serial monitor (Ctrl+C to exit)'
    & $cli monitor --port $Port --config baudrate=115200
}
