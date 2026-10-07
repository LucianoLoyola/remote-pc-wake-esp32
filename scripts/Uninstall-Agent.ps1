<#
.SYNOPSIS
    Removes the Remote PC Wake agent from this PC.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-Agent.ps1

.NOTES
    CHANGES MADE TO THIS PC: deletes the "Remote PC Wake Agent" task, the RemotePcWakeAgent
      firewall rule and C:\ProgramData\RemotePcWake\.
    NETWORK ACCESS: none.
    Full reference: docs/scripts-reference.md
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:ProgramData 'RemotePcWake'
$TaskName = 'Remote PC Wake Agent'

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName'."
}

Remove-NetFirewallRule -Name 'RemotePcWakeAgent' -ErrorAction SilentlyContinue
Write-Host 'Removed firewall rule.'

if (Test-Path $InstallDir) {
    Remove-Item -Recurse -Force $InstallDir
    Write-Host "Removed $InstallDir."
}

Write-Host 'Remote PC Wake agent uninstalled.'
