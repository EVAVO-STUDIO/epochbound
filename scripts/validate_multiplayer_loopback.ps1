param(
    [Parameter(Mandatory = $true)] [string]$GodotExecutable,
    [Parameter(Mandatory = $true)] [string]$ProjectRoot,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Format-ProcessArgument {
    param([Parameter(Mandatory = $true)] [string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-LoopbackPeer {
    param(
        [Parameter(Mandatory = $true)] [string]$Role,
        [Parameter(Mandatory = $true)] [int]$Port,
        [Parameter(Mandatory = $true)] [string]$ReceiptPath,
        [Parameter(Mandatory = $true)] [string]$ReadyPath,
        [Parameter(Mandatory = $true)] [string]$RunRoot
    )

    $stdoutPath = Join-Path $RunRoot "$Role.stdout.log"
    $stderrPath = Join-Path $RunRoot "$Role.stderr.log"
    $arguments = @(
        "--headless",
        "--path",
        $ProjectRoot,
        "--script",
        "res://tools/multiplayer_loopback_peer_driver.gd",
        "--",
        "--role=$Role",
        "--port=$Port",
        "--receipt=$ReceiptPath",
        "--timeout=45"
    )
    if ($Role -eq "host") {
        $arguments += "--ready=$ReadyPath"
    }
    $formatted = $arguments | ForEach-Object { Format-ProcessArgument $_ }
    $process = Start-Process `
        -FilePath $GodotExecutable `
        -ArgumentList $formatted `
        -WorkingDirectory $ProjectRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -NoNewWindow `
        -PassThru

    return [pscustomobject]@{
        Role = $Role
        Process = $process
        ReceiptPath = $ReceiptPath
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}

function Stop-LoopbackPeer {
    param([Parameter(Mandatory = $true)] $Peer)
    try {
        $Peer.Process.Refresh()
        if (-not $Peer.Process.HasExited) {
            try {
                $Peer.Process.Kill($true)
            }
            catch {
                Stop-Process -Id $Peer.Process.Id -Force -ErrorAction SilentlyContinue
            }
            $Peer.Process.WaitForExit(5000) | Out-Null
        }
    }
    catch {
        # Cleanup is best effort; the validation error is reported separately.
    }
}

function Write-PeerLogs {
    param([Parameter(Mandatory = $true)] $Peer)
    Write-Host "`n--- $($Peer.Role) stdout ---"
    if (Test-Path $Peer.StdoutPath) {
        Get-Content -Raw $Peer.StdoutPath | Write-Host
    }
    Write-Host "--- $($Peer.Role) stderr ---"
    if (Test-Path $Peer.StderrPath) {
        Get-Content -Raw $Peer.StderrPath | Write-Host
    }
}

function Write-AllPeerLogs {
    param([Parameter(Mandatory = $true)] [array]$Peers)
    foreach ($peer in $Peers) {
        Write-PeerLogs $peer
    }
}

function Read-Receipt {
    param(
        [Parameter(Mandatory = $true)] [string]$Role,
        [Parameter(Mandatory = $true)] [string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "Real ENet loopback $Role receipt is missing: $Path"
    }
    $receipt = Get-Content -Raw $Path | ConvertFrom-Json
    if ($null -eq $receipt -or -not [bool]$receipt.ok) {
        $message = if ($null -ne $receipt) { [string]$receipt.error } else { "invalid JSON receipt" }
        throw "Real ENet loopback $Role failed: $message"
    }
    return $receipt
}

function Assert-PeerLogClean {
    param([Parameter(Mandatory = $true)] $Peer)
    $combined = ""
    if (Test-Path $Peer.StdoutPath) {
        $combined += Get-Content -Raw $Peer.StdoutPath
    }
    if (Test-Path $Peer.StderrPath) {
        $combined += "`n" + (Get-Content -Raw $Peer.StderrPath)
    }
    if (
        $combined -match "SCRIPT ERROR:" -or
        $combined -match "(?m)^ERROR:" -or
        $combined -match "handle_crash:" -or
        $combined -match "Program crashed with signal"
    ) {
        throw "Real ENet loopback $($Peer.Role) emitted a Godot parser, runtime or native crash error."
    }
}

function Test-AllReceiptsPresent {
    param([Parameter(Mandatory = $true)] [array]$Peers)
    foreach ($peer in $Peers) {
        if (-not (Test-Path $peer.ReceiptPath)) {
            return $false
        }
    }
    return $true
}

function Save-EnvironmentValue {
    param(
        [Parameter(Mandatory = $true)] [hashtable]$Snapshot,
        [Parameter(Mandatory = $true)] [string]$Name
    )
    $Snapshot[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Restore-EnvironmentValue {
    param(
        [Parameter(Mandatory = $true)] [hashtable]$Snapshot,
        [Parameter(Mandatory = $true)] [string]$Name
    )
    $value = $Snapshot[$Name]
    if ($null -eq $value) {
        [Environment]::SetEnvironmentVariable($Name, $null, "Process")
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, [string]$value, "Process")
    }
}

$runRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "epochbound-enet-loopback-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$environmentSnapshot = @{}
$environmentKeys = @(
    "XDG_DATA_HOME",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
    "APPDATA",
    "LOCALAPPDATA"
)
foreach ($key in $environmentKeys) {
    Save-EnvironmentValue -Snapshot $environmentSnapshot -Name $key
}
$isolatedUserRoot = Join-Path $runRoot "godot-user"
$isolatedDataRoot = Join-Path $isolatedUserRoot "data"
$isolatedConfigRoot = Join-Path $isolatedUserRoot "config"
$isolatedCacheRoot = Join-Path $isolatedUserRoot "cache"
foreach ($path in @($isolatedDataRoot, $isolatedConfigRoot, $isolatedCacheRoot)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}
$env:XDG_DATA_HOME = $isolatedDataRoot
$env:XDG_CONFIG_HOME = $isolatedConfigRoot
$env:XDG_CACHE_HOME = $isolatedCacheRoot
$env:APPDATA = $isolatedDataRoot
$env:LOCALAPPDATA = $isolatedCacheRoot

$port = 32000 + ($PID % 10000)
$readyPath = Join-Path $runRoot "host-ready.json"
$hostReceiptPath = Join-Path $runRoot "host.json"
$allyReceiptPath = Join-Path $runRoot "ally.json"
$invaderReceiptPath = Join-Path $runRoot "invader.json"
$peers = @()

try {
    Write-Host "`n==> Smoke test real ENet host ally and invader loopback on UDP $port"
    Write-Host "Isolated Godot user data: $isolatedUserRoot"
    $hostPeer = Start-LoopbackPeer `
        -Role "host" `
        -Port $port `
        -ReceiptPath $hostReceiptPath `
        -ReadyPath $readyPath `
        -RunRoot $runRoot
    $peers += $hostPeer

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path $readyPath) -and [DateTime]::UtcNow -lt $readyDeadline) {
        $hostPeer.Process.Refresh()
        if ($hostPeer.Process.HasExited) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path $readyPath)) {
        Write-AllPeerLogs -Peers $peers
        throw "Real ENet loopback host did not open its UDP listener."
    }

    $allyPeer = Start-LoopbackPeer `
        -Role "ally" `
        -Port $port `
        -ReceiptPath $allyReceiptPath `
        -ReadyPath $readyPath `
        -RunRoot $runRoot
    $peers += $allyPeer
    Start-Sleep -Milliseconds 800
    $invaderPeer = Start-LoopbackPeer `
        -Role "invader" `
        -Port $port `
        -ReceiptPath $invaderReceiptPath `
        -ReadyPath $readyPath `
        -RunRoot $runRoot
    $peers += $invaderPeer

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $earlyExitRole = ""
    while (-not (Test-AllReceiptsPresent -Peers $peers) -and [DateTime]::UtcNow -lt $deadline) {
        foreach ($peer in $peers) {
            $peer.Process.Refresh()
            if ($peer.Process.HasExited -and -not (Test-Path $peer.ReceiptPath)) {
                $earlyExitRole = [string]$peer.Role
                break
            }
        }
        if (-not [string]::IsNullOrEmpty($earlyExitRole)) {
            break
        }
        Start-Sleep -Milliseconds 100
    }

    if (-not [string]::IsNullOrEmpty($earlyExitRole)) {
        Write-AllPeerLogs -Peers $peers
        throw "Real ENet loopback $earlyExitRole exited before producing transport evidence."
    }

    if (-not (Test-AllReceiptsPresent -Peers $peers)) {
        Write-AllPeerLogs -Peers $peers
        throw "Real ENet loopback did not produce all three receipts within $TimeoutSeconds seconds."
    }

    # Each peer atomically promotes its complete receipt. Give redirected logs
    # one bounded interval to become visible before reviewing all child output.
    Start-Sleep -Milliseconds 300

    Write-AllPeerLogs -Peers $peers
    foreach ($peer in $peers) {
        $peer.Process.Refresh()
        if ($peer.Process.HasExited) {
            throw "Real ENet loopback $($peer.Role) exited before harness-owned cleanup."
        }
        Assert-PeerLogClean $peer
    }

    $hostReceipt = Read-Receipt -Role "host" -Path $hostReceiptPath
    $allyReceipt = Read-Receipt -Role "ally" -Path $allyReceiptPath
    $invaderReceipt = Read-Receipt -Role "invader" -Path $invaderReceiptPath

    if (
        [int]$hostReceipt.peer_count -ne 3 -or
        [int]$hostReceipt.ally_count -ne 1 -or
        [int]$hostReceipt.invader_count -ne 1 -or
        [int]$hostReceipt.input_peer_count -ne 2 -or
        [int]$hostReceipt.protocol_version -ne 1 -or
        [int]$hostReceipt.snapshot_wire_bytes -le 0 -or
        [int]$hostReceipt.snapshot_wire_bytes -gt 1200 -or
        [int]$hostReceipt.snapshot_uncompressed_bytes -le [int]$hostReceipt.snapshot_wire_bytes -or
        [string]$hostReceipt.map_id -ne "clockwood_edge" -or
        [string]$hostReceipt.era_id -ne "ashen" -or
        [string]$hostReceipt.area_id -ne "clockwood_ashen_hunt"
    ) {
        throw "Real ENet loopback host receipt did not prove the complete bounded authoritative exchange."
    }

    foreach ($receipt in @($allyReceipt, $invaderReceipt)) {
        $expectedRole = [string]$receipt.role
        if (
            [int]$receipt.local_peer_id -le 1 -or
            [string]$receipt.local_role -ne $expectedRole -or
            [int]$receipt.peer_count -ne 3 -or
            [int]$receipt.snapshot_sequence -lt 0 -or
            [int]$receipt.input_sequence_sent -le 10000 -or
            [string]$receipt.map_id -ne "clockwood_edge" -or
            [string]$receipt.era_id -ne "ashen"
        ) {
            throw "Real ENet loopback $expectedRole receipt did not prove input transmission and authoritative snapshot restoration."
        }
    }

    Write-Host (
        "Real ENet loopback passed: host, ally and invader negotiated through UDP; " +
        "both repeated production input RPCs reached host authority; both clients restored authoritative snapshots; " +
        "and the compressed snapshot stayed within the 1200-byte transport budget."
    )
}
finally {
    # The parent harness deliberately owns termination after receipt validation.
    # This gate validates transport exchange, not Godot's independent headless
    # process-exit or graceful-disconnect lifecycle.
    foreach ($peer in $peers) {
        Stop-LoopbackPeer $peer
    }
    foreach ($key in $environmentKeys) {
        Restore-EnvironmentValue -Snapshot $environmentSnapshot -Name $key
    }
    if (Test-Path $runRoot) {
        Remove-Item -Recurse -Force $runRoot -ErrorAction SilentlyContinue
    }
}
