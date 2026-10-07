<#
.SYNOPSIS
    Gives this PC a fixed IP address, for routers that can't reserve one (Runbook 01, B4).

.DESCRIPTION
    The ESP32 finds the PC by its IP address, so the address must not change.
    The best way is a DHCP reservation in the router. If your router doesn't allow it,
    this script sets a fixed address on the PC's wired adapter instead:

      1. Reads the current settings (gateway, subnet, DNS servers) to reuse them.
      2. Checks that the new address is in the same network and not used by another device.
      3. Applies the fixed address.
      4. Checks that the router is still reachable; if it isn't, restores automatic
         addressing (DHCP) so the PC doesn't stay offline.

    The network drops for a few seconds while the address changes.
    Use -UseDhcp to go back to automatic addressing.

.PARAMETER IpAddress
    The fixed address for this PC, e.g. 192.168.1.211. Choose one outside the range
    your router hands out (high addresses such as .200-.250 usually are).

.PARAMETER UseDhcp
    Undo: go back to getting the address automatically from the router.

.PARAMETER AdapterName
    Adapter to configure (e.g. "Ethernet"). Detected automatically by default.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Set-StaticIp.ps1 -IpAddress 192.168.1.211

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Set-StaticIp.ps1 -UseDhcp

.NOTES
    CHANGES MADE TO THIS PC, on the selected wired adapter only:
      - Turns off DHCP and sets the fixed IPv4 address, the subnet and the default gateway
        (the gateway currently in use)
      - Sets the DNS servers to the ones currently in use (or the gateway)
      - -UseDhcp: turns DHCP back on and removes the fixed address, gateway and DNS servers
    NETWORK ACCESS: pings the new address (to check it's free) and the gateway (to check the result).
    UNDO: run again with -UseDhcp, or Settings > Network & internet > Ethernet > IP assignment > Automatic.
    Full reference: docs/scripts-reference.md
#>
#Requires -RunAsAdministrator
[CmdletBinding(DefaultParameterSetName = 'Static')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Static')]
    [string]$IpAddress,

    [Parameter(Mandatory = $true, ParameterSetName = 'Dhcp')]
    [switch]$UseDhcp,

    [string]$AdapterName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

function ConvertTo-UInt32([string]$Address) {
    $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Test-SameSubnet([string]$First, [string]$Second, [int]$PrefixLength) {
    # e.g. /24 -> 2^32 - 2^8 = 255.255.255.0
    $mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $PrefixLength))
    return ((ConvertTo-UInt32 $First) -band $mask) -eq ((ConvertTo-UInt32 $Second) -band $mask)
}

function Test-Reachable([string]$Address) {
    return [bool](Test-Connection -ComputerName $Address -Count 2 -Quiet -ErrorAction SilentlyContinue)
}

function Wait-Gateway([string]$Gateway) {
    for ($i = 0; $i -lt 10; $i++) {
        if (Test-Reachable $Gateway) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Enable-Dhcp($Adapter) {
    $index = $Adapter.ifIndex
    Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -PrefixOrigin Manual -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false
    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
    Invoke-NativeQuiet 'ipconfig.exe' @('/renew', $Adapter.Name) | Out-Null
}

# ---------------------------------------------------------------------------
Write-Step 'Selecting the network adapter'
$adapter = Get-WakeAdapter $AdapterName
$config = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$current = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
$dhcpEnabled = (Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).Dhcp -eq 'Enabled'
Write-Ok "$($adapter.Name) - $($adapter.InterfaceDescription)"
Write-Info "Current address: $($current.IPAddress)/$($current.PrefixLength) ($(if ($dhcpEnabled) { 'automatic, DHCP' } else { 'fixed' }))"

if ($UseDhcp) {
    Write-Step 'Switching back to automatic addressing (DHCP)'
    Enable-Dhcp $adapter
    Start-Sleep -Seconds 3
    $new = Get-AdapterIPv4 $adapter
    Write-Ok "DHCP enabled. Current address: $new"
    Write-Info "If the ESP32 must reach this PC, update PC_IP_ADDRESS in config.h and flash it again."
    return
}

# ---------------------------------------------------------------------------
Write-Step 'Checking the new address'
$parsed = $null
if (-not [System.Net.IPAddress]::TryParse($IpAddress, [ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork') {
    throw "Invalid IPv4 address: $IpAddress"
}
$gateway = $config.IPv4DefaultGateway.NextHop | Select-Object -First 1
if (-not $gateway) {
    throw 'This adapter has no default gateway; connect it to the router first.'
}
$prefix = $current.PrefixLength
if (-not (Test-SameSubnet $IpAddress $gateway $prefix)) {
    throw "$IpAddress is not in the same network as the router ($gateway/$prefix)."
}
if ($IpAddress -eq $gateway) {
    throw "$IpAddress is the router's own address."
}
if ($IpAddress -ne $current.IPAddress -and (Test-Reachable $IpAddress)) {
    throw "$IpAddress is already used by another device. Choose a different address."
}
$dns = @($config.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
if ($dns.Count -eq 0) { $dns = @($gateway) }
Write-Ok "$IpAddress is free. Gateway: $gateway, prefix: /$prefix, DNS: $($dns -join ', ')"

# ---------------------------------------------------------------------------
Write-Step "Setting the fixed address $IpAddress"
Write-Info 'The network drops for a few seconds...'
$index = $adapter.ifIndex
Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false
New-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -IPAddress $IpAddress -PrefixLength $prefix -DefaultGateway $gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dns

Write-Step 'Verifying'
if (-not (Wait-Gateway $gateway)) {
    Write-Warn 'The router is not reachable with the new address. Restoring automatic addressing (DHCP)...'
    Enable-Dhcp $adapter
    throw 'The fixed address did not work and DHCP was restored. Check the address and try again.'
}
Write-Ok "Router reachable. This PC now always uses $IpAddress."

Write-Step 'Next steps'
Write-Info 'config.h must point to the new address. New-FirmwareConfig.ps1 detects it automatically:'
Write-Host '             powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1'
Write-Info 'Then flash the ESP32 again with Install-Firmware.ps1.'
Write-Info 'To undo: run this script with -UseDhcp.'
