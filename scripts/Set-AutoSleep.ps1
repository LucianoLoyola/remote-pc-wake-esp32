<#
.SYNOPSIS
    Makes the PC go to sleep by itself after a period of inactivity (Runbook 04, Part F).

.DESCRIPTION
    Sets the "sleep after" time used while the PC is plugged in. Useful so the PC
    doesn't stay on for hours after you disconnect; /wake brings it back.

.PARAMETER Minutes
    Minutes of inactivity before sleeping. 0 = never sleep.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Set-AutoSleep.ps1 -Minutes 60
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 1440)]
    [int]$Minutes
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Common.ps1"

Write-Step 'Setting the sleep timeout (plugged in)'
if ((Invoke-NativeQuiet 'powercfg.exe' @('/change', 'standby-timeout-ac', "$Minutes")) -ne 0) {
    throw 'powercfg failed to change the sleep timeout.'
}

if ($Minutes -eq 0) {
    Write-Ok 'The PC will never go to sleep by itself.'
}
else {
    Write-Ok "The PC will go to sleep after $Minutes minutes of inactivity."
}
