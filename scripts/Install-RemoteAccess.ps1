<#
.SYNOPSIS
    Sets up remote access to this PC: Tailscale (private network) + Remote Desktop.

.DESCRIPTION
    Run it on the TARGET PC (the one you wake with the ESP32). It:
      1. Installs Tailscale (via winget) if it isn't installed yet.
      2. Signs in to Tailscale and enables "Run unattended", so the PC stays
         reachable at the login screen after a Wake-on-LAN boot.
      3. Enables Remote Desktop with Network Level Authentication
         (Windows Pro/Enterprise/Education only).
      4. Checks for common pitfalls (key expiry, passwordless Microsoft accounts)
         and prints how to connect.

    The script is safe to run more than once.

.PARAMETER AuthKey
    Optional Tailscale auth key (https://login.tailscale.com/admin/settings/keys)
    to sign in without a browser.

.PARAMETER SkipRemoteDesktop
    Only set up Tailscale. Use it on Windows Home or if you prefer RustDesk/Parsec.

.PARAMETER RestrictRdpToTailscale
    Limit Remote Desktop to connections coming from Tailscale and the local network.

.PARAMETER AllowPasswordSignIn
    Turn off "only allow Windows Hello sign-in for Microsoft accounts", which makes
    Remote Desktop reject your password. Sign out and sign in once with your password afterwards.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-RemoteAccess.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-RemoteAccess.ps1 -RestrictRdpToTailscale -AllowPasswordSignIn
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$AuthKey,
    [switch]$SkipRemoteDesktop,
    [switch]$RestrictRdpToTailscale,
    [switch]$AllowPasswordSignIn
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

$TailscaleExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$AdminConsoleUrl = 'https://login.tailscale.com/admin/machines'
# Language-independent name of the built-in "Remote Desktop" firewall group
$RdpFirewallGroup = '@FirewallAPI.dll,-28752'
$TailscaleRanges = @('100.64.0.0/10', 'fd7a:115c:a1e0::/48')

function Get-TailscaleStatus {
    $json = & $TailscaleExe status --json
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    return ($json | Out-String | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
Write-Step 'Installing Tailscale'

if (Test-Path $TailscaleExe) {
    Write-Ok 'Tailscale is already installed.'
}
else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install Tailscale manually from https://tailscale.com/download/windows and run this script again.'
    }
    winget install --id tailscale.tailscale -e --silent --accept-source-agreements --accept-package-agreements
    if (-not (Test-Path $TailscaleExe)) {
        throw 'Tailscale installation failed. Install it manually from https://tailscale.com/download/windows and run this script again.'
    }
    Write-Ok 'Tailscale installed.'
}

# Wait for the Tailscale service to answer
$status = $null
for ($i = 0; $i -lt 30 -and -not $status; $i++) {
    $status = Get-TailscaleStatus
    if (-not $status) { Start-Sleep -Seconds 1 }
}
if (-not $status) {
    throw 'The Tailscale service is not responding. Restart the PC and run this script again.'
}

# ---------------------------------------------------------------------------
Write-Step 'Signing in to Tailscale (unattended mode)'

if ($status.BackendState -eq 'Running') {
    Write-Ok "Already signed in as $($status.User.($status.Self.UserID.ToString()).LoginName)."
    & $TailscaleExe set --unattended
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'Unattended mode enabled.'
    }
    else {
        Write-Warn 'Could not enable unattended mode automatically.'
        Write-Info 'Enable it by hand: Tailscale tray icon -> Preferences -> Run unattended.'
    }
}
else {
    $upArgs = @('up', '--unattended')
    if ($AuthKey) {
        $upArgs += "--auth-key=$AuthKey"
    }
    else {
        Write-Info 'A sign-in link will appear below. Open it in a browser and log in.'
        Write-Info 'Use the SAME account on your phone/laptop.'
    }
    & $TailscaleExe @upArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Tailscale sign-in failed. Run the script again.'
    }
    Write-Ok 'Signed in. Unattended mode enabled.'
}

$status = Get-TailscaleStatus
$self = $status.Self
$machineName = $self.DNSName.Split('.')[0]
$tailscaleIp = $self.TailscaleIPs | Where-Object { $_ -match '^\d+\.' } | Select-Object -First 1

if ($self.KeyExpiry) {
    Write-Warn "This PC's Tailscale key expires on $($self.KeyExpiry)."
    Write-Info 'After that you must sign in again AT the PC. Disable key expiry for this machine:'
    Write-Info "$AdminConsoleUrl  ->  '$machineName'  ->  ...  ->  Disable key expiry"
}
else {
    Write-Ok 'Key expiry is disabled for this PC.'
}

# ---------------------------------------------------------------------------
$rdpEnabled = $false
$editionId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID

if ($SkipRemoteDesktop) {
    Write-Step 'Skipping Remote Desktop (-SkipRemoteDesktop)'
}
elseif ($editionId -like 'Core*') {
    Write-Step 'Remote Desktop'
    Write-Warn "Windows Home ($editionId) can't host Remote Desktop sessions."
    Write-Info 'Use RustDesk, Parsec or Chrome Remote Desktop instead (see Runbook 04).'
}
else {
    Write-Step 'Enabling Remote Desktop'

    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
    Enable-NetFirewallRule -Group $RdpFirewallGroup
    Write-Ok 'Remote Desktop enabled (with Network Level Authentication).'

    if ($RestrictRdpToTailscale) {
        Get-NetFirewallRule -Group $RdpFirewallGroup |
            Set-NetFirewallRule -RemoteAddress ($TailscaleRanges + 'LocalSubnet')
        Write-Ok 'Remote Desktop restricted to Tailscale and the local network.'
    }
    $rdpEnabled = $true

    # Account checks
    $localUser = Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue
    if ($localUser -and $localUser.PrincipalSource -eq 'MicrosoftAccount') {
        Write-Info 'You sign in with a Microsoft account: use its EMAIL and PASSWORD (not the PIN) in Remote Desktop.'

        $passwordlessKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
        $passwordless = Get-ItemProperty $passwordlessKey -Name DevicePasswordLessBuildVersion -ErrorAction SilentlyContinue
        if ($passwordless -and $passwordless.DevicePasswordLessBuildVersion -eq 2) {
            if ($AllowPasswordSignIn) {
                Set-ItemProperty -Path $passwordlessKey -Name DevicePasswordLessBuildVersion -Value 0 -Type DWord
                Write-Ok 'Password sign-in allowed for Microsoft accounts.'
                Write-Warn 'Sign out and sign in once WITH YOUR PASSWORD (not the PIN) so Remote Desktop accepts it.'
            }
            else {
                Write-Warn 'Windows Hello-only sign-in is enabled. Remote Desktop will reject your password.'
                Write-Info 'Run this script again with -AllowPasswordSignIn, then sign out and sign in once with your password.'
            }
        }
    }
}

# ---------------------------------------------------------------------------
Write-Step 'Done. How to connect from anywhere'

Write-Info "Tailscale name : $machineName"
Write-Info "Tailscale IP   : $tailscaleIp"
Write-Host ''
Write-Info '1. Install Tailscale on your phone/laptop and sign in with the same account.'
if ($rdpEnabled) {
    Write-Info "2. Open the Windows App (or run: mstsc /v:$machineName) and connect to '$machineName'."
}
else {
    Write-Info "2. Connect your remote-control app (RustDesk, Parsec...) to '$machineName' or $tailscaleIp."
}
Write-Host ''
Write-Info 'Never forward port 3389 on your router. Always connect through Tailscale.'
