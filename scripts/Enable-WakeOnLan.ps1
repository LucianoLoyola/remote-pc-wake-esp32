<#
.SYNOPSIS
    Configures Windows so this PC can be powered on with Wake-on-LAN (Runbook 01, Part B).

.DESCRIPTION
    On the PC you want to wake:
      1. Picks the wired (Ethernet) adapter.
      2. Enables "Wake on Magic Packet" and "Shutdown Wake-On-Lan", disables wake on pattern
         and the energy-saving features that can cut the link while the PC is off.
      3. Stops Windows from turning the adapter off to save power.
      4. Arms the adapter to wake the PC.
      5. Disables Fast Startup.
      6. Prints the MAC and IP for config.h and the router's DHCP reservation.

    The BIOS/UEFI settings (Runbook 01, Part A) can't be changed from Windows: do them first.

    The network connection drops for a few seconds while the adapter restarts.
    Safe to run more than once.

.PARAMETER AdapterName
    Adapter to configure (e.g. "Ethernet"). Detected automatically by default.

.PARAMETER CheckOnly
    Only report the current configuration; change nothing. Doesn't require Administrator.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Enable-WakeOnLan.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Enable-WakeOnLan.ps1 -CheckOnly

.NOTES
    CHANGES MADE TO THIS PC (none with -CheckOnly), on the selected wired adapter only:
      - Advanced properties, if the driver has them: Wake on Magic Packet on, Wake on pattern off,
        Shutdown Wake-On-Lan on, Enable PME on, Energy-Efficient Ethernet / Advanced EEE / Green Ethernet off
      - Power management: wake on magic packet on, wake on pattern off
      - Registry: adapter key under HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-...}: PnPCapabilities = 24
      - powercfg /deviceenablewake "<adapter>"
      - Registry: HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power: HiberbootEnabled = 0
      - Restarts the adapter if a setting changed (network drops for a few seconds)
    NETWORK ACCESS: none.
    UNDO: Device Manager (adapter Advanced / Power Management tabs), HiberbootEnabled = 1,
      powercfg /devicedisablewake "<adapter>".
    Full reference: docs/scripts-reference.md
#>
[CmdletBinding()]
param(
    [string]$AdapterName,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

if (-not $CheckOnly) { Assert-Admin }

# Advanced adapter properties, by registry keyword (language-independent).
# Only the ones the driver exposes are changed.
$DesiredProperties = [ordered]@{
    '*WakeOnMagicPacket'  = '1'  # Wake on Magic Packet
    '*WakeOnPattern'      = '0'  # Wake on pattern match (causes random wake-ups)
    'S5WakeOnLan'         = '1'  # Realtek: Shutdown Wake-On-Lan
    'EnablePME'           = '1'  # Intel: Enable PME (wake from power off)
    '*EEE'                = '0'  # Energy-Efficient Ethernet
    'AdvancedEEE'         = '0'  # Realtek: Advanced EEE
    'EnableGreenEthernet' = '0'  # Realtek: Green Ethernet
}

$NetClassKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
$PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
# PnPCapabilities = 24 unchecks "Allow the computer to turn off this device to save power"
$PnPCapabilitiesNoPowerOff = 24

function Get-AdapterClassKey($Adapter) {
    Get-ChildItem $NetClassKey -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -Name NetCfgInstanceId -ErrorAction SilentlyContinue).NetCfgInstanceId -eq $Adapter.InterfaceGuid
    } | Select-Object -First 1
}

function Test-WakeArmed($Adapter) {
    $ErrorActionPreference = 'Continue'
    $armed = & powercfg.exe /devicequery wake_armed 2>&1
    return [bool]($armed | Where-Object { $_.ToString().Trim() -eq $Adapter.InterfaceDescription })
}

# ---------------------------------------------------------------------------
Write-Step 'Selecting the network adapter'
$adapter = Get-WakeAdapter $AdapterName
$ip = Get-AdapterIPv4 $adapter
Write-Ok "$($adapter.Name) - $($adapter.InterfaceDescription)"

if (-not $CheckOnly) {
    # -------------------------------------------------------------------------
    Write-Step 'Configuring the adapter'
    $changed = $false
    foreach ($keyword in $DesiredProperties.Keys) {
        $property = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -ErrorAction SilentlyContinue
        if (-not $property) { continue }
        $value = $DesiredProperties[$keyword]
        if ($property.ValidRegistryValues -and $property.ValidRegistryValues -notcontains $value) { continue }
        if (($property.RegistryValue -join '') -ne $value) {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -RegistryValue $value -NoRestart
            $changed = $true
        }
        Write-Ok "$($property.DisplayName) = $value"
    }

    try {
        Set-NetAdapterPowerManagement -Name $adapter.Name -WakeOnMagicPacket Enabled -WakeOnPattern Disabled -NoRestart
        Write-Ok 'Power management: wake on magic packet only.'
    }
    catch {
        Write-Warn "Could not set power management through Windows: $($_.Exception.Message)"
    }

    $classKey = Get-AdapterClassKey $adapter
    if ($classKey) {
        $current = (Get-ItemProperty $classKey.PSPath -Name PnPCapabilities -ErrorAction SilentlyContinue).PnPCapabilities
        if ($current -ne $PnPCapabilitiesNoPowerOff) {
            Set-ItemProperty -Path $classKey.PSPath -Name PnPCapabilities -Value $PnPCapabilitiesNoPowerOff -Type DWord
            $changed = $true
        }
        Write-Ok 'Windows will not turn the adapter off to save power.'
    }
    else {
        Write-Warn 'Adapter registry key not found; uncheck "Allow the computer to turn off this device" manually.'
    }

    if ($changed) {
        Write-Info 'Restarting the adapter to apply the changes (network drops for a few seconds)...'
        Restart-NetAdapter -Name $adapter.Name
        for ($i = 0; $i -lt 30 -and (Get-NetAdapter -Name $adapter.Name).Status -ne 'Up'; $i++) { Start-Sleep -Seconds 1 }
    }

    if (-not (Test-WakeArmed $adapter)) {
        if ((Invoke-NativeQuiet 'powercfg.exe' @('/deviceenablewake', $adapter.InterfaceDescription)) -ne 0) {
            Write-Warn 'Could not arm the adapter to wake the PC; enable it in Device Manager (Power Management tab).'
        }
    }

    # -------------------------------------------------------------------------
    Write-Step 'Disabling Fast Startup'
    Set-ItemProperty -Path $PowerKey -Name HiberbootEnabled -Value 0 -Type DWord
    Write-Ok 'Fast Startup disabled.'
}

# ---------------------------------------------------------------------------
Write-Step 'Verification'
$problems = 0

$magic = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*WakeOnMagicPacket' -ErrorAction SilentlyContinue
if (-not $magic) {
    Write-Warn 'The driver does not expose "Wake on Magic Packet". Install the latest driver from the motherboard vendor.'
    $problems++
}
elseif (($magic.RegistryValue -join '') -eq '1') {
    Write-Ok 'Wake on Magic Packet: enabled'
}
else {
    Write-Warn 'Wake on Magic Packet: disabled'
    $problems++
}

$s5 = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'S5WakeOnLan' -ErrorAction SilentlyContinue
if ($s5 -and ($s5.RegistryValue -join '') -ne '1') {
    Write-Warn 'Shutdown Wake-On-Lan: disabled (the PC will only wake from sleep)'
    $problems++
}

if (Test-WakeArmed $adapter) {
    Write-Ok 'Adapter is allowed to wake the PC'
}
else {
    Write-Warn 'Adapter is NOT allowed to wake the PC'
    $problems++
}

$hiberboot = (Get-ItemProperty -Path $PowerKey -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
if ($hiberboot -eq 0) {
    Write-Ok 'Fast Startup: disabled'
}
else {
    Write-Warn 'Fast Startup: enabled (Wake-on-LAN from shutdown will likely fail)'
    $problems++
}

Write-Info 'BIOS/UEFI settings cannot be checked from Windows (Runbook 01, Part A).'

# ---------------------------------------------------------------------------
Write-Step 'Values for the next steps'
Write-Info "MAC address : $(Format-Mac $adapter.MacAddress)"
Write-Info "IP address  : $ip"
Write-Host ''
Write-Info '1. In your router, reserve this IP for this MAC address (DHCP reservation, Runbook 01 B4).'
Write-Info '2. config.h:'
Write-Host "             #define PC_MAC        `"$(Format-Mac $adapter.MacAddress)`""
Write-Host "             #define PC_IP_ADDRESS `"$ip`""
Write-Info '3. Test: shut down the PC and wake it from another device (Runbook 01 B5).'

if ($problems -gt 0) {
    Write-Host "`n$problems problem(s) found." -ForegroundColor Yellow
    if ($CheckOnly) { Write-Host 'Run without -CheckOnly (as Administrator) to fix them.' -ForegroundColor Yellow }
}
