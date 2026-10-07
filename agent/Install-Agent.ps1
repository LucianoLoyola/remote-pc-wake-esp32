<#
.SYNOPSIS
    Installs the Remote PC Wake agent on this PC.

.DESCRIPTION
    - Copies the agent to %ProgramData%\RemotePcWake (readable by Administrators and SYSTEM only)
    - Generates a random shared token (or keeps the existing one)
    - Opens the agent port in Windows Firewall, only for the ESP32 (or the local subnet)
    - Registers a scheduled task that runs the agent as SYSTEM at startup
    - Tests the agent and prints the values for the firmware's config.h

    Safe to run again to update the agent; the token is kept unless -NewToken is given.

.PARAMETER Esp32Address
    IP address of the ESP32. Only this address may talk to the agent.
    Defaults to LocalSubnet (any device on your local network).

.PARAMETER Port
    TCP port the agent listens on. Default: 8765.

.PARAMETER NewToken
    Generate a new token even if one already exists.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\agent\Install-Agent.ps1 -Esp32Address 192.168.1.50
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$Esp32Address = 'LocalSubnet',
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,
    [switch]$NewToken
)

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:ProgramData 'RemotePcWake'
$AgentPath = Join-Path $InstallDir 'RemotePcWakeAgent.ps1'
$ConfigPath = Join-Path $InstallDir 'config.json'
$TaskName = 'Remote PC Wake Agent'
$FirewallRuleName = 'RemotePcWakeAgent'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "    [OK] $Text" -ForegroundColor Green }

function New-Token {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
}

# ---------------------------------------------------------------------------
Write-Step 'Stopping any running agent'
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName
    Write-Ok 'Previous agent stopped.'
}

# ---------------------------------------------------------------------------
Write-Step "Installing files to $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Force -Path (Join-Path $PSScriptRoot 'RemotePcWakeAgent.ps1') -Destination $AgentPath

$token = $null
$diskWarningPercent = 90
if ((Test-Path $ConfigPath) -and -not $NewToken) {
    $existing = Get-Content -Raw $ConfigPath | ConvertFrom-Json
    $token = $existing.Token
    if ($existing.DiskWarningPercent) { $diskWarningPercent = $existing.DiskWarningPercent }
}
$tokenIsNew = -not $token
if ($tokenIsNew) { $token = New-Token }

$config = [ordered]@{
    Token              = $token
    Port               = $Port
    ListenAddress      = '+'
    DiskWarningPercent = $diskWarningPercent
}
ConvertTo-Json -InputObject $config | Set-Content -Encoding UTF8 -Path $ConfigPath

# Only SYSTEM (S-1-5-18) and Administrators (S-1-5-32-544) may read the token.
# SIDs are used because group names are translated on non-English Windows.
& icacls.exe $InstallDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to set folder permissions.' }
Write-Ok 'Agent and config installed (folder restricted to Administrators and SYSTEM).'

# ---------------------------------------------------------------------------
Write-Step 'Configuring Windows Firewall'
Remove-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue
New-NetFirewallRule -Name $FirewallRuleName -DisplayName 'Remote PC Wake Agent' `
    -Description 'Allows the Remote PC Wake ESP32 to reach the agent.' `
    -Direction Inbound -Protocol TCP -LocalPort $Port -RemoteAddress $Esp32Address `
    -Action Allow -Profile Any | Out-Null
Write-Ok "Port $Port open for: $Esp32Address"

# ---------------------------------------------------------------------------
Write-Step 'Registering the startup task'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AgentPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description 'Lets the Remote PC Wake ESP32 control this PC.' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Ok "Task '$TaskName' registered and started."

# ---------------------------------------------------------------------------
Write-Step 'Testing the agent'
$status = $null
for ($i = 0; $i -lt 30 -and -not $status; $i++) {
    try {
        $status = Invoke-RestMethod -Uri "http://localhost:$Port/api/status" -Headers @{ 'X-Agent-Token' = $token } -TimeoutSec 3
    }
    catch {
        Start-Sleep -Seconds 1
    }
}
if (-not $status) {
    throw "The agent did not answer. Check $InstallDir\agent.log and Task Scheduler ('$TaskName')."
}
Write-Ok "Agent $($status.agentVersion) is answering on port $Port (host $($status.hostname))."

# ---------------------------------------------------------------------------
$pcIp = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.PrefixOrigin -in 'Dhcp', 'Manual' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'Tailscale' } |
    Select-Object -ExpandProperty IPAddress -First 1

Write-Step 'Done'
if ($tokenIsNew) {
    Write-Host '    A new token was generated. Put these lines in firmware/remote-pc-wake/config.h and re-flash the ESP32:' -ForegroundColor Yellow
}
else {
    Write-Host '    Existing token kept. Your config.h should contain:' -ForegroundColor Yellow
}
Write-Host ''
Write-Host "    #define AGENT_TOKEN `"$token`""
Write-Host "    #define AGENT_PORT  $Port"
Write-Host ''
Write-Host "    PC_IP_ADDRESS in config.h must be this PC's LAN IP (probably $pcIp)."
Write-Host '    Keep the token secret: anyone with it can shut down this PC from your network.'
