# Shared helpers for the setup scripts. Dot-source it: . "$PSScriptRoot\lib\Common.ps1"

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "    [OK]   $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "    [WARN] $Text" -ForegroundColor Yellow }
function Write-Info([string]$Text) { Write-Host "           $Text" }

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw 'This script must run as Administrator. Right-click Start -> Terminal (Admin), then run it again.'
    }
}

# Runs a native command and returns its exit code. Native tools write errors to stderr,
# which would abort a script running with $ErrorActionPreference = 'Stop'.
function Invoke-NativeQuiet([string]$FilePath, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & $FilePath @Arguments 2>&1 | Out-Null
    return $LASTEXITCODE
}

# Reloads PATH from the registry so tools installed by winget in this session are found.
function Sync-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

# The wired adapter used for Wake-on-LAN: physical, Ethernet (802.3), connected.
# If several qualify, the one carrying the default route wins.
function Get-WakeAdapter([string]$Name) {
    if ($Name) {
        return Get-NetAdapter -Name $Name
    }
    $candidates = @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.PhysicalMediaType -eq '802.3' })
    if ($candidates.Count -eq 0) {
        throw 'No connected Ethernet adapter found. Wake-on-LAN needs the PC connected by cable. Use -AdapterName to pick one.'
    }
    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $candidates.ifIndex -contains $_.ifIndex } |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        return $candidates | Where-Object { $_.ifIndex -eq $route.ifIndex }
    }
    return $candidates[0]
}

function Get-AdapterIPv4($Adapter) {
    return Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        Select-Object -ExpandProperty IPAddress -First 1
}

# "AA-BB-CC-DD-EE-FF" -> "AA:BB:CC:DD:EE:FF"
function Format-Mac([string]$Mac) {
    return $Mac.Replace('-', ':').ToUpperInvariant()
}

# USB-to-serial chips found on ESP32 boards, by USB vendor ID.
$Script:Esp32UsbVendors = @{
    'VID_10C4' = 'Silicon Labs CP210x'
    'VID_1A86' = 'WCH CH340/CH9102'
    'VID_303A' = 'Espressif native USB'
    'VID_0403' = 'FTDI'
}

# Serial ports that look like an ESP32 board: @{ Port = 'COM3'; Chip = '...'; Status = 'OK' }
function Get-Esp32SerialPort {
    $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match ($Script:Esp32UsbVendors.Keys -join '|') }
    foreach ($device in $devices) {
        $vendor = $Script:Esp32UsbVendors.Keys | Where-Object { $device.InstanceId -match $_ } | Select-Object -First 1
        $port = if ($device.FriendlyName -match '\((COM\d+)\)') { $Matches[1] } else { $null }
        [pscustomobject]@{
            Port   = $port
            Chip   = $Script:Esp32UsbVendors[$vendor]
            Status = $device.Status
            Name   = $device.FriendlyName
        }
    }
}

function Find-ArduinoCli {
    $command = Get-Command arduino-cli -ErrorAction SilentlyContinue
    if (-not $command) {
        Sync-SessionPath
        $command = Get-Command arduino-cli -ErrorAction SilentlyContinue
    }
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\arduino-cli.exe'),
        (Join-Path $env:ProgramFiles 'Arduino CLI\arduino-cli.exe')
    )
    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
