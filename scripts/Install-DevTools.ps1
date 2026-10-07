<#
.SYNOPSIS
    Installs everything needed to build and flash the ESP32 firmware (Runbook 02).

.DESCRIPTION
    1. Installs Git, Arduino IDE 2 and Arduino CLI with winget (skips what's already installed).
    2. Installs the ESP32 board package (Espressif) and the libraries
       UniversalTelegramBot and ArduinoJson. Arduino IDE and Arduino CLI share them.
    3. Checks the USB driver of a connected ESP32 board.

    Doesn't require Administrator (winget may ask for permission while installing).
    The ESP32 board package is several hundred MB.

.PARAMETER SkipIde
    Don't install Arduino IDE (command line only).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-DevTools.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipIde
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

$Esp32BoardsUrl = 'https://espressif.github.io/arduino-esp32/package_esp32_index.json'
$Libraries = @('UniversalTelegramBot', 'ArduinoJson')
$DriverLinks = @{
    'Silicon Labs CP210x' = 'https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers'
    'WCH CH340/CH9102'    = 'https://www.wch-ic.com/downloads/CH341SER_EXE.html'
    'FTDI'                = 'https://ftdichip.com/drivers/vcp-drivers/'
}

function Install-WingetPackage([string]$Id, [string]$Name) {
    $ErrorActionPreference = 'Continue'
    & winget list --id $Id -e --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$Name is already installed."
        return
    }
    Write-Info "Installing $Name..."
    & winget install --id $Id -e --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $Name (winget exit code $LASTEXITCODE)."
    }
    Write-Ok "$Name installed."
}

function Invoke-ArduinoCli([string[]]$Arguments) {
    & $script:cli @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "arduino-cli $($Arguments -join ' ') failed."
    }
}

# ---------------------------------------------------------------------------
Write-Step 'Installing tools'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not available. Install "App Installer" from the Microsoft Store and run this script again.'
}
Install-WingetPackage 'Git.Git' 'Git'
if (-not $SkipIde) {
    Install-WingetPackage 'ArduinoSA.IDE.stable' 'Arduino IDE'
}
Install-WingetPackage 'ArduinoSA.CLI' 'Arduino CLI'

$script:cli = Find-ArduinoCli
if (-not $script:cli) {
    throw 'arduino-cli was installed but not found. Open a new terminal and run this script again.'
}

# ---------------------------------------------------------------------------
Write-Step 'Installing the ESP32 board package (this can take several minutes)'
Invoke-ArduinoCli @('core', 'update-index', '--additional-urls', $Esp32BoardsUrl)
Invoke-ArduinoCli @('core', 'install', 'esp32:esp32', '--additional-urls', $Esp32BoardsUrl)
Write-Ok 'ESP32 board package installed.'

Write-Step 'Installing libraries'
Invoke-ArduinoCli (@('lib', 'install') + $Libraries)
Write-Ok "Libraries installed: $($Libraries -join ', ')"

# ---------------------------------------------------------------------------
Write-Step 'Checking the ESP32 USB connection'
$boards = @(Get-Esp32SerialPorts)
if ($boards.Count -eq 0) {
    Write-Warn 'No ESP32 board detected. Connect it with a USB DATA cable and run this check again:'
    Write-Info 'powershell -ExecutionPolicy Bypass -File .\scripts\Install-DevTools.ps1'
}
foreach ($board in $boards) {
    if ($board.Status -eq 'OK' -and $board.Port) {
        Write-Ok "$($board.Chip) on $($board.Port)"
    }
    else {
        Write-Warn "$($board.Chip) found, but its driver is missing or not working."
        if ($DriverLinks.ContainsKey($board.Chip)) {
            Write-Info "Install the driver from $($DriverLinks[$board.Chip]), then unplug and re-plug the board."
        }
    }
}

Write-Step 'Done'
Write-Info 'Next: create config.h with scripts\New-FirmwareConfig.ps1 (Runbook 03).'
