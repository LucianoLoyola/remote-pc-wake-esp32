<#
.SYNOPSIS
    Remote PC Wake agent: a small HTTP service that lets the ESP32 control this PC.

.DESCRIPTION
    Runs in the background (scheduled task as SYSTEM, installed by Install-Agent.ps1)
    and listens on the local network for requests from the ESP32.

    Every request must carry the shared token in the "X-Agent-Token" header.

    Endpoints:
      GET  /api/status                 PC status and stats (CPU, RAM, disks, GPU, warnings)
      POST /api/shutdown?delay=<sec>   Shut down (optionally after a delay)
      POST /api/restart?delay=<sec>    Restart (optionally after a delay)
      POST /api/sleep                  Sleep
      POST /api/lock                   Lock the session at the PC's screen
      POST /api/cancel                 Cancel a scheduled shutdown/restart

.PARAMETER ConfigPath
    Path to config.json. Defaults to %ProgramData%\RemotePcWake\config.json.

.NOTES
    WHAT IT DOES WHILE RUNNING (as SYSTEM, started by Task Scheduler):
      - Listens on TCP port 8765 and only answers requests carrying the token
      - Allowed actions: status, shutdown, restart, sleep, lock, cancel. It can't run commands sent to it.
      - Runs shutdown.exe and, if installed, nvidia-smi
      - Writes C:\ProgramData\RemotePcWake\agent.log (rotated at 1 MB)
    NETWORK ACCESS: no outgoing connections; only answers requests from the local network.
    UNDO: scripts\Uninstall-Agent.ps1
    Full reference: docs/scripts-reference.md
#>
param(
    [string]$ConfigPath = (Join-Path $env:ProgramData 'RemotePcWake\config.json')
)

$ErrorActionPreference = 'Stop'
$AgentVersion = '1.0.0'
$MaxDelaySeconds = 86400
$MinShutdownDelaySeconds = 5  # gives the agent time to answer before Windows goes down

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
if (-not $config.Token -or $config.Token.Length -lt 16) {
    throw "config.json must contain a Token of at least 16 characters."
}
$port = if ($config.Port) { [int]$config.Port } else { 8765 }
$listenAddress = if ($config.ListenAddress) { $config.ListenAddress } else { '+' }
$diskWarningPercent = if ($config.DiskWarningPercent) { [int]$config.DiskWarningPercent } else { 90 }
$logPath = Join-Path (Split-Path $ConfigPath) 'agent.log'

# Shutdown or restart scheduled through the agent: @{ Action = 'shutdown'; At = [datetime] }
$script:pending = $null

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RemotePcWakeNative {
    [DllImport("powrprof.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.I1)]
    static extern bool SetSuspendState(
        [MarshalAs(UnmanagedType.I1)] bool hibernate,
        [MarshalAs(UnmanagedType.I1)] bool forceCritical,
        [MarshalAs(UnmanagedType.I1)] bool disableWakeEvent);

    [DllImport("kernel32.dll")]
    static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("wtsapi32.dll", SetLastError = true)]
    static extern bool WTSDisconnectSession(IntPtr server, int sessionId, bool wait);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct TokenPrivilege {
        public int Count;
        public long Luid;
        public int Attributes;
    }

    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LookupPrivilegeValue(string system, string name, out long luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivilege newState,
                                             int length, IntPtr previous, IntPtr returnLength);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    const uint TOKEN_QUERY = 0x0008;
    const int SE_PRIVILEGE_ENABLED = 0x0002;
    const uint NO_CONSOLE_SESSION = 0xFFFFFFFF;

    static void EnableShutdownPrivilege() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token)) {
            return;
        }
        TokenPrivilege privilege;
        privilege.Count = 1;
        privilege.Attributes = SE_PRIVILEGE_ENABLED;
        LookupPrivilegeValue(null, "SeShutdownPrivilege", out privilege.Luid);
        AdjustTokenPrivileges(token, false, ref privilege, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(token);
    }

    public static bool Sleep() {
        EnableShutdownPrivilege();
        return SetSuspendState(false, false, false);
    }

    // Disconnecting the console session shows the lock screen; apps keep running.
    public static bool LockConsole() {
        uint sessionId = WTSGetActiveConsoleSessionId();
        if (sessionId == NO_CONSOLE_SESSION) {
            return false;
        }
        return WTSDisconnectSession(IntPtr.Zero, (int)sessionId, false);
    }
}
'@

function Write-Log([string]$Message) {
    try {
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB) {
            Move-Item -Force $logPath "$logPath.old"
        }
        Add-Content -Path $logPath -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Message)
    }
    catch {
        # Logging must never stop the agent
        Write-Verbose "Could not write to the log: $($_.Exception.Message)"
    }
}

function Send-Json($Context, [int]$StatusCode, $Body) {
    $json = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response = $Context.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = 'application/json; charset=utf-8'
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
}

function Get-Uptime {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    return [int]((Get-Date) - $boot).TotalSeconds
}

function Get-GpuInfo {
    $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $nvidiaSmi) { return $null }
    try {
        $line = & $nvidiaSmi.Source --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader,nounits |
            Select-Object -First 1
        $parts = $line -split ',\s*'
        return [ordered]@{
            name               = $parts[0]
            temperatureC       = [int]$parts[1]
            utilizationPercent = [int]$parts[2]
        }
    }
    catch {
        return $null
    }
}

function Get-PendingAction {
    if (-not $script:pending) { return $null }
    $remaining = [int]($script:pending.At - (Get-Date)).TotalSeconds
    if ($remaining -lt 0) {
        $script:pending = $null
        return $null
    }
    return [ordered]@{ action = $script:pending.Action; secondsRemaining = $remaining }
}

function Get-Status {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    $user = (Get-CimInstance Win32_ComputerSystem).UserName

    $totalKb = [double]$os.TotalVisibleMemorySize
    $memoryUsedPercent = [math]::Round((1 - ($os.FreePhysicalMemory / $totalKb)) * 100)

    $warnings = @()
    $disks = @()
    foreach ($disk in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        if (-not $disk.Size) { continue }
        $usedPercent = [math]::Round((1 - ($disk.FreeSpace / $disk.Size)) * 100)
        $disks += [ordered]@{
            drive       = $disk.DeviceID
            usedPercent = $usedPercent
            freeGB      = [math]::Round($disk.FreeSpace / 1GB, 1)
        }
        if ($usedPercent -ge $diskWarningPercent) {
            $warnings += "Disk $($disk.DeviceID) is $usedPercent% full"
        }
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $warnings += 'Windows Update needs a restart'
    }

    return [ordered]@{
        agentVersion  = $AgentVersion
        hostname      = $env:COMPUTERNAME
        user          = $user
        uptimeSeconds = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds
        cpuPercent    = [int]$cpu.PercentProcessorTime
        memory        = [ordered]@{
            usedPercent = $memoryUsedPercent
            totalGB     = [math]::Round($totalKb / 1MB, 1)
        }
        disks         = $disks
        gpu           = Get-GpuInfo
        pendingAction = Get-PendingAction
        warnings      = $warnings
    }
}

function Get-RequestedDelay($Request) {
    $raw = $Request.QueryString['delay']
    if (-not $raw) { return 0 }
    $value = 0
    if (-not [int]::TryParse($raw, [ref]$value) -or $value -lt 0 -or $value -gt $MaxDelaySeconds) {
        throw [System.ArgumentException]"delay must be between 0 and $MaxDelaySeconds seconds"
    }
    return $value
}

function Format-Delay([int]$Seconds) {
    if ($Seconds -lt 60) { return "$Seconds s" }
    return "$([math]::Round($Seconds / 60)) min"
}

# Runs shutdown.exe and returns its exit code. shutdown.exe reports errors on stderr,
# which would abort the script under $ErrorActionPreference = 'Stop'.
function Invoke-ShutdownExe([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & shutdown.exe @Arguments 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-ShutdownCommand([string]$Action, [int]$DelaySeconds) {
    $delay = [math]::Max($DelaySeconds, $MinShutdownDelaySeconds)
    $flag = if ($Action -eq 'restart') { '/r' } else { '/s' }

    # Replace any shutdown already scheduled
    Invoke-ShutdownExe @('/a') | Out-Null
    $exitCode = Invoke-ShutdownExe @($flag, '/f', '/t', "$delay", '/c', "Remote PC Wake: $Action requested remotely.")
    if ($exitCode -ne 0) {
        throw "shutdown.exe failed with exit code $exitCode"
    }

    $script:pending = @{ Action = $Action; At = (Get-Date).AddSeconds($delay) }
    $verb = if ($Action -eq 'restart') { 'Restarting' } else { 'Shutting down' }
    return "$verb in $(Format-Delay $delay)."
}

function Invoke-Request($Context) {
    $request = $Context.Request
    $path = $request.Url.AbsolutePath.TrimEnd('/').ToLowerInvariant()
    $method = $request.HttpMethod

    if ($request.Headers['X-Agent-Token'] -cne $config.Token) {
        Write-Log "401 $method $path from $($request.RemoteEndPoint)"
        Send-Json $Context 401 @{ ok = $false; message = 'Invalid or missing token' }
        return
    }

    if ($method -eq 'GET' -and $path -eq '/api/status') {
        Send-Json $Context 200 (Get-Status)
        return
    }

    if ($method -ne 'POST') {
        Send-Json $Context 404 @{ ok = $false; message = 'Not found' }
        return
    }

    Write-Log "$method $($request.Url.PathAndQuery) from $($request.RemoteEndPoint)"
    switch ($path) {
        { $_ -in '/api/shutdown', '/api/restart' } {
            $action = $path.Substring(5)
            $message = Invoke-ShutdownCommand $action (Get-RequestedDelay $request)
            Send-Json $Context 200 ([ordered]@{ ok = $true; message = $message; uptimeSeconds = Get-Uptime })
        }
        '/api/cancel' {
            $cancelled = ((Invoke-ShutdownExe @('/a')) -eq 0)
            $script:pending = $null
            $message = if ($cancelled) { 'Scheduled shutdown/restart cancelled.' } else { 'Nothing to cancel.' }
            Send-Json $Context 200 @{ ok = $true; message = $message }
        }
        '/api/lock' {
            if ([RemotePcWakeNative]::LockConsole()) {
                Send-Json $Context 200 @{ ok = $true; message = 'Screen locked.' }
            }
            else {
                Send-Json $Context 500 @{ ok = $false; message = 'Could not lock the session.' }
            }
        }
        '/api/sleep' {
            # Answer first: once the PC is asleep it can't reply.
            Send-Json $Context 200 @{ ok = $true; message = 'Going to sleep.' }
            Start-Sleep -Seconds 2
            if (-not [RemotePcWakeNative]::Sleep()) {
                Write-Log 'SetSuspendState failed'
            }
        }
        default {
            Send-Json $Context 404 @{ ok = $false; message = 'Not found' }
        }
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://${listenAddress}:$port/")
$listener.Start()
Write-Log "Agent $AgentVersion listening on port $port"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
        Invoke-Request $context
    }
    catch [System.ArgumentException] {
        Send-Json $context 400 @{ ok = $false; message = $_.Exception.Message }
    }
    catch {
        Write-Log "Error: $($_.Exception.Message)"
        try {
            Send-Json $context 500 @{ ok = $false; message = $_.Exception.Message }
        }
        catch {
            Write-Log "Could not send the error response: $($_.Exception.Message)"
        }
    }
}
