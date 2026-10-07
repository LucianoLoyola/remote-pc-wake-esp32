<#
.SYNOPSIS
    Sends a Wake-on-LAN magic packet to a PC on the local network.

.DESCRIPTION
    Use it from a SECOND computer on the same network to confirm that the
    target PC wakes up before involving the ESP32. If this script can't wake
    the PC, the problem is in the BIOS or Windows settings, not the ESP32.

.EXAMPLE
    .\Send-MagicPacket.ps1 -MacAddress "AA:BB:CC:DD:EE:FF"

.EXAMPLE
    .\Send-MagicPacket.ps1 -MacAddress "AA-BB-CC-DD-EE-FF" -Broadcast "192.168.0.255"

.NOTES
    CHANGES MADE TO THIS PC: none. Sends a UDP broadcast (port 9) on the local network.
    NETWORK ACCESS: local network only.
    Full reference: docs/scripts-reference.md
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$MacAddress,

    [string]$Broadcast = "255.255.255.255",

    [int]$Port = 9
)

$clean = $MacAddress -replace '[:\-\.\s]', ''
if ($clean -notmatch '^[0-9A-Fa-f]{12}$') {
    throw "Invalid MAC address '$MacAddress'. Expected format AA:BB:CC:DD:EE:FF"
}

$macBytes = for ($i = 0; $i -lt 12; $i += 2) { [Convert]::ToByte($clean.Substring($i, 2), 16) }
$packet = [byte[]](@(0xFF) * 6 + $macBytes * 16)

$client = New-Object System.Net.Sockets.UdpClient
try {
    $client.EnableBroadcast = $true
    $endpoint = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse($Broadcast)), $Port
    for ($i = 0; $i -lt 3; $i++) {
        [void]$client.Send($packet, $packet.Length, $endpoint)
        Start-Sleep -Milliseconds 100
    }
    Write-Host "Magic packet sent to $MacAddress via ${Broadcast}:$Port"
}
finally {
    $client.Close()
}
