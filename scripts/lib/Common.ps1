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

# The interface that carries the PC's LAN address. Usually it's the wired adapter itself,
# but with a Hyper-V external virtual switch (Hyper-V, some WSL2/Docker setups) the
# address lives on a "vEthernet" adapter bound to it.
function Get-LanInterface($Adapter) {
    $candidates = @($Adapter) + @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -like 'Hyper-V Virtual Ethernet Adapter*' })
    foreach ($candidate in $candidates) {
        $address = Get-NetIPAddress -InterfaceIndex $candidate.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        $config = Get-NetIPConfiguration -InterfaceIndex $candidate.ifIndex -ErrorAction SilentlyContinue
        $gateway = $config.IPv4DefaultGateway.NextHop | Select-Object -First 1
        if ($address -and $gateway) {
            return [pscustomobject]@{
                InterfaceIndex = $candidate.ifIndex
                Name           = $candidate.Name
                IPAddress      = $address.IPAddress
                PrefixLength   = [int]$address.PrefixLength
                Gateway        = $gateway
                DnsServers     = @($config.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
                Dhcp           = (Get-NetIPInterface -InterfaceIndex $candidate.ifIndex -AddressFamily IPv4).Dhcp -eq 'Enabled'
                IsVirtual      = $candidate.ifIndex -ne $Adapter.ifIndex
            }
        }
    }
    return $null
}

function Get-AdapterIPv4($Adapter) {
    $lan = Get-LanInterface $Adapter
    if ($lan) { return $lan.IPAddress }
    return $null
}

# ---------- IPv4 helpers ----------

function ConvertTo-UInt32([string]$Address) {
    $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-UInt32([uint32]$Value) {
    $bytes = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]$bytes).ToString()
}

# e.g. /24 -> 2^32 - 2^8 = 255.255.255.0
function Get-PrefixMask([int]$PrefixLength) {
    return [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $PrefixLength))
}

function ConvertTo-SubnetMask([int]$PrefixLength) {
    return ConvertFrom-UInt32 (Get-PrefixMask $PrefixLength)
}

function Test-SameSubnet([string]$First, [string]$Second, [int]$PrefixLength) {
    $mask = Get-PrefixMask $PrefixLength
    return ((ConvertTo-UInt32 $First) -band $mask) -eq ((ConvertTo-UInt32 $Second) -band $mask)
}

function Test-IPv4Address([string]$Address) {
    $parsed = $null
    return [System.Net.IPAddress]::TryParse($Address, [ref]$parsed) -and $parsed.AddressFamily -eq 'InterNetwork' -and
        $Address -match '^\d{1,3}(\.\d{1,3}){3}$'
}

# Whether any device on the local network uses this address. A ping alone isn't enough
# (Windows blocks it by default), but sending one makes Windows ask "who has this address?"
# over ARP, and every device answers that, so the ARP table tells the truth.
function Test-IPv4InUse([string]$Address) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        if ($ping.Send($Address, 700).Status -eq 'Success') { return $true }
    }
    catch {
        Write-Verbose "Ping to $Address failed: $($_.Exception.Message)"
    }
    finally {
        $ping.Dispose()
    }
    $neighbor = Get-NetNeighbor -IPAddress $Address -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.State -in 'Reachable', 'Stale', 'Delay', 'Probe', 'Permanent' -and
            $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' }
    return [bool]$neighbor
}

# Suggests a free address in the gateway's network, searching from near the top down:
# routers usually hand out addresses from the bottom of the range.
function Find-FreeIPv4Address([string]$Gateway, [int]$PrefixLength, [string[]]$Exclude) {
    $mask = Get-PrefixMask $PrefixLength
    $network = (ConvertTo-UInt32 $Gateway) -band $mask
    $broadcast = $network + [uint32]([math]::Pow(2, 32 - $PrefixLength)) - 1
    $own = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
    $skip = @($Gateway) + $own + $Exclude
    $start = [math]::Max($broadcast - 5, $network + 2)
    for ($n = $start; $n -gt $network + 1 -and $n -gt $start - 40; $n--) {
        $candidate = ConvertFrom-UInt32 ([uint32]$n)
        if ($skip -contains $candidate) { continue }
        if (-not (Test-IPv4InUse $candidate)) { return $candidate }
    }
    return $null
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
