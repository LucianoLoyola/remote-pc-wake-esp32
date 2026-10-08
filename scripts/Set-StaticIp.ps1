<#
.SYNOPSIS
    Gives this PC a fixed IP address, for routers that can't reserve one (Runbook 01, B4).

.DESCRIPTION
    The ESP32 finds the PC by its IP address, so the address must not change.
    The best way is a DHCP reservation in the router. If your router doesn't allow it,
    this script sets a fixed address on the PC instead:

      1. Finds the interface that holds the PC's LAN address: the wired adapter, or the
         Hyper-V "vEthernet" adapter bound to it when a Hyper-V external switch is used.
      2. Without -IpAddress, suggests a free address near the top of your network
         (routers usually hand out addresses from the bottom) and asks you to confirm.
         With -IpAddress auto, uses the suggested address without asking.
      3. Checks that the address is in the same network and that no device uses it
         (ping and ARP, so devices that block ping are detected too).
      4. Applies the fixed address, reusing the current gateway, subnet and DNS servers.
      5. Checks that the router is still reachable; if it isn't, restores automatic
         addressing (DHCP) so the PC doesn't stay offline.

    The network drops for a few seconds while the address changes.
    Use -UseDhcp to go back to automatic addressing.

.PARAMETER IpAddress
    The fixed address for this PC, e.g. 192.168.1.250. If omitted, a free one is suggested.
    "auto" picks a free one without asking (for unattended runs, such as the WakeDesk app).

.PARAMETER UseDhcp
    Undo: go back to getting the address automatically from the router.

.PARAMETER AdapterName
    Wired adapter to use (e.g. "Ethernet"). Detected automatically by default.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Set-StaticIp.ps1
    Suggests a free address and asks before applying it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Set-StaticIp.ps1 -IpAddress 192.168.1.250

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Set-StaticIp.ps1 -UseDhcp

.NOTES
    CHANGES MADE TO THIS PC, on the interface that holds the LAN address only:
      - Turns off DHCP and sets the fixed IPv4 address, the subnet and the default gateway
        (the gateway currently in use)
      - Sets the DNS servers to the ones currently in use (or the gateway)
      - -UseDhcp: turns DHCP back on and removes the fixed address, gateway and DNS servers
    NETWORK ACCESS: local network only. Pings candidate addresses (and reads the ARP table)
      to find a free one, and pings the gateway to check the result.
    UNDO: run again with -UseDhcp, or Settings > Network & internet > Ethernet > IP assignment > Automatic.
    Full reference: docs/scripts-reference.md
#>
#Requires -RunAsAdministrator
[CmdletBinding(DefaultParameterSetName = 'Static')]
param(
    [Parameter(ParameterSetName = 'Static')]
    [string]$IpAddress,

    [Parameter(Mandatory = $true, ParameterSetName = 'Dhcp')]
    [switch]$UseDhcp,

    [string]$AdapterName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

function Wait-Gateway([string]$Gateway) {
    for ($i = 0; $i -lt 10; $i++) {
        if (Test-Connection -ComputerName $Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Enable-Dhcp([int]$InterfaceIndex) {
    Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -PrefixOrigin Manual -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false
    Set-NetIPInterface -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ResetServerAddresses
    $alias = (Get-NetAdapter -InterfaceIndex $InterfaceIndex).Name
    Invoke-NativeQuiet 'ipconfig.exe' @('/renew', $alias) | Out-Null
}

# ---------------------------------------------------------------------------
Write-Step 'Finding the LAN interface'
$adapter = Get-WakeAdapter $AdapterName
$lan = Get-LanInterface $adapter
if (-not $lan) {
    throw "No IPv4 address with a gateway found on $($adapter.Name). Connect the PC to the router and try again."
}
Write-Ok "$($lan.Name): $($lan.IPAddress)/$($lan.PrefixLength), gateway $($lan.Gateway) ($(if ($lan.Dhcp) { 'automatic, DHCP' } else { 'fixed' }))"
if ($lan.IsVirtual) {
    Write-Warn "A Hyper-V virtual switch is in use: the address lives on '$($lan.Name)', not on '$($adapter.Name)'."
    Write-Info 'That interface is the one configured. Wake-on-LAN still uses the physical adapter.'
}

if ($UseDhcp) {
    Write-Step 'Switching back to automatic addressing (DHCP)'
    Enable-Dhcp $lan.InterfaceIndex
    Start-Sleep -Seconds 3
    Write-Ok "DHCP enabled. Current address: $(Get-AdapterIPv4 $adapter)"
    Write-Info 'If the ESP32 must reach this PC, update config.h (New-FirmwareConfig.ps1) and flash it again.'
    return
}

# ---------------------------------------------------------------------------
Write-Step 'Choosing the address'
$auto = $IpAddress -eq 'auto'
if (-not $IpAddress -or $auto) {
    Write-Info 'Looking for a free address near the top of your network...'
    $suggested = Find-FreeIPv4Address $lan.Gateway $lan.PrefixLength @()
    if (-not $suggested) {
        throw 'No free address found near the top of the network. Pass one with -IpAddress.'
    }
    $answer = if ($auto) { 'y' } else { Read-Host -Prompt "Use $suggested for this PC? [Y/n]" }
    if ($answer -and $answer -notmatch '^(y|yes|s|si)$') {
        Write-Info 'Cancelled. Run again with -IpAddress to choose a specific address.'
        return
    }
    $IpAddress = $suggested
}

if (-not (Test-IPv4Address $IpAddress)) {
    throw "Invalid IPv4 address: $IpAddress"
}
if (-not (Test-SameSubnet $IpAddress $lan.Gateway $lan.PrefixLength)) {
    throw "$IpAddress is not in your network ($($lan.Gateway)/$($lan.PrefixLength)). Use an address like $(Find-FreeIPv4Address $lan.Gateway $lan.PrefixLength @())."
}
$mask = Get-PrefixMask $lan.PrefixLength
$network = (ConvertTo-UInt32 $lan.Gateway) -band $mask
$broadcast = $network + [uint32]([math]::Pow(2, 32 - $lan.PrefixLength)) - 1
$value = ConvertTo-UInt32 $IpAddress
if ($value -eq $network -or $value -eq $broadcast) {
    throw "$IpAddress is the network or broadcast address; it can't be used by a device."
}
if ($IpAddress -eq $lan.Gateway) {
    throw "$IpAddress is the router's own address."
}
if ($IpAddress -ne $lan.IPAddress -and (Test-IPv4InUse $IpAddress)) {
    throw "$IpAddress is already used by another device. Choose a different address."
}
$dns = $lan.DnsServers
if (-not $dns -or $dns.Count -eq 0) { $dns = @($lan.Gateway) }
Write-Ok "$IpAddress is free. Gateway: $($lan.Gateway), prefix: /$($lan.PrefixLength), DNS: $($dns -join ', ')"

# ---------------------------------------------------------------------------
Write-Step "Setting the fixed address $IpAddress"
Write-Info 'The network drops for a few seconds...'
$index = $lan.InterfaceIndex
Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false
New-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -IPAddress $IpAddress -PrefixLength $lan.PrefixLength -DefaultGateway $lan.Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dns

Write-Step 'Verifying'
if (-not (Wait-Gateway $lan.Gateway)) {
    Write-Warn 'The router is not reachable with the new address. Restoring automatic addressing (DHCP)...'
    Enable-Dhcp $index
    throw 'The fixed address did not work and DHCP was restored. Check the address and try again.'
}
Write-Ok "Router reachable. This PC now always uses $IpAddress."

Write-Step 'Next steps'
Write-Info 'config.h must point to the new address. New-FirmwareConfig.ps1 detects it automatically:'
Write-Host '             powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1'
Write-Info 'Then flash the ESP32 again with Install-Firmware.ps1.'
Write-Info 'To undo: run this script with -UseDhcp.'
