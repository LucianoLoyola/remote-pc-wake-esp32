<#
.SYNOPSIS
    Checks every PowerShell script in the repository. The same checks run on GitHub for pull requests to main and on main.

.DESCRIPTION
    1. Syntax: every script must parse in Windows PowerShell 5.1 (the version shipped with Windows).
    2. Forbidden patterns: no script may download and run code, or hide code
       (Invoke-Expression, DownloadString, encoded commands, Base64-decoded code...).
    3. PSScriptAnalyzer: Microsoft's static analyzer, with the rules in PSScriptAnalyzerSettings.psd1.

    Exits with code 1 if any error or warning is found.

    Requires the PSScriptAnalyzer module:
        Install-Module PSScriptAnalyzer -Scope CurrentUser

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tests\Invoke-ScriptAnalysis.ps1

.NOTES
    CHANGES MADE TO THIS PC: none; it only reads the repository's files.
    NETWORK ACCESS: none.
    Full reference: docs/scripts-reference.md
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SettingsPath = Join-Path $RepoRoot 'PSScriptAnalyzerSettings.psd1'
$OnGitHub = [bool]$env:GITHUB_ACTIONS

# Patterns that would let a script run code it didn't ship with, or hide what it does.
$ForbiddenPatterns = [ordered]@{
    'Invoke-Expression'    = 'Invoke-Expression'
    'iex alias'            = '(^|[\s|;(])iex([\s(]|$)'
    'DownloadString'       = 'DownloadString'
    'DownloadFile'         = 'DownloadFile'
    'Encoded command'      = '-Enc(odedCommand)?\b'
    'Base64-decoded code'  = 'FromBase64String'
    'BITS download'        = 'Start-BitsTransfer'
    'Add-Type from a file' = 'Add-Type\s+-Path'
}

$failures = 0
$scripts = Get-ChildItem -Path $RepoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

function Get-RelativePath([string]$Path) {
    return $Path.Substring($RepoRoot.Length + 1).Replace('\', '/')
}

function Write-Finding([string]$Level, [string]$File, [int]$Line, [string]$Message) {
    if ($OnGitHub) {
        # GitHub shows these as annotations on the changed lines
        Write-Output "::$Level file=$File,line=$Line::$Message"
    }
    else {
        Write-Output ("  {0,-7} {1}:{2}  {3}" -f $Level.ToUpper(), $File, $Line, $Message)
    }
}

# ---------------------------------------------------------------------------
Write-Output "Checking $($scripts.Count) files"

Write-Output "`n[1/3] Syntax (Windows PowerShell $($PSVersionTable.PSVersion))"
foreach ($script in $scripts) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$errors)
    foreach ($e in $errors) {
        Write-Finding 'error' (Get-RelativePath $script.FullName) $e.Extent.StartLineNumber $e.Message
        $failures++
    }
}

Write-Output "`n[2/3] Forbidden patterns"
foreach ($script in $scripts) {
    if ($script.FullName -eq $PSCommandPath) { continue }  # this file lists the patterns
    foreach ($name in $ForbiddenPatterns.Keys) {
        $found = Select-String -Path $script.FullName -Pattern $ForbiddenPatterns[$name]
        foreach ($match in $found) {
            Write-Finding 'error' (Get-RelativePath $script.FullName) $match.LineNumber "Forbidden pattern: $name"
            $failures++
        }
    }
}

Write-Output "`n[3/3] PSScriptAnalyzer"
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
Import-Module PSScriptAnalyzer
$results = Invoke-ScriptAnalyzer -Path $RepoRoot -Recurse -Settings $SettingsPath
foreach ($result in $results) {
    $blocking = $result.Severity -in 'Error', 'Warning', 'ParseError'
    $level = if ($blocking) { 'error' } else { 'notice' }
    Write-Finding $level (Get-RelativePath $result.ScriptPath) $result.Line "$($result.RuleName): $($result.Message)"
    if ($blocking) { $failures++ }
}

# ---------------------------------------------------------------------------
if ($failures -gt 0) {
    Write-Output "`nFAILED: $failures problem(s) found."
    exit 1
}
Write-Output "`nPASSED: no problems found."
