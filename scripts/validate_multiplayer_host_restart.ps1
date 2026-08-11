param(
    [Parameter(Mandatory = $true)] [string]$GodotExecutable,
    [Parameter(Mandatory = $true)] [string]$ProjectRoot,
    [int]$TimeoutSeconds = 75
)

$ErrorActionPreference = "Stop"

function Format-ProcessArgument {
    param([Parameter(Mandatory = $true)] [string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-RestartPeer {
    param(
        [Parameter(Mandatory = $true)] [string]$Label,
        [Parameter(Mandatory = $true)] [string]$Role,
        [Parameter(Mandatory = $true)] [int]$Port,
        [Parameter(Mandatory = $true)] [string]$ReceiptPath,
        [Parameter(Mandatory = $true)] [string]$RunRoot,
        [int]$Generation = 0,
        [string]$ReadyPath = "",
        [string]$ExchangePath = "",
        [string]$InitialPath = "",
        [string]$RecoveryPath = "",
        [string]$StandbyPath = "",
        [string]$ActivationPath = ""
    )

    $stdoutPath = Join-Path $RunRoot "$Label.stdout.log"
    $stderrPath = Join-Path $RunRoot "$Label.stderr.log"
    $arguments = @(
        "--headless",
        "--path",
        $ProjectRoot,
        "--script",
        "res://tools/multiplayer_host_restart_peer.gd",
        "--",
        "--role=$Role",
        "--port=$Port",
        "--receipt=$ReceiptPath",
        "--timeout=60"
    )
    if ($Generation -gt 0) {
        $arguments += "--generation=$Generation"
    }
    if (-not [string]::IsNullOrWhiteSpace($ReadyPath)) {
        $arguments += "--ready=$ReadyPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExchangePath)) {
        $arguments += "--exchange=$ExchangePath"
    }
    if (-not [string]::IsNullOrWhiteSpace($InitialPath)) {
        $arguments += "--initial=$InitialPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($RecoveryPath)) {
        $arguments += "--recovery=$RecoveryPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($StandbyPath)) {
        $arguments += "--standby=$StandbyPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($ActivationPath)) {
        $arguments += "--activation=$ActivationPath"
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
        Label = $Label
        Role = $Role
        Generation = $Generation
        Process = $process
        ReceiptPath = $ReceiptPath
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}

function Stop-RestartPeer {
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
        # Bounded cleanup only; the primary validation error is retained.
    }
}

function Force-Terminate-OriginalHost {
    param([Parameter(Mandatory = $true)] $Peer)
    $Peer.Process.Refresh()
    if ($Peer.Process.HasExited) {
        throw "Original host exited before the harness could simulate process loss."
    }
    try {
        $Peer.Process.Kill($true)
    }
    catch {
        Stop-Process -Id $Peer.Process.Id -Force -ErrorAction Stop
    }
    if (-not $Peer.Process.WaitForExit(10000)) {
        throw "Original host process did not terminate after forced process loss."
    }
    Write-Host "FORCED ORIGINAL HOST PROCESS LOSS: pid $($Peer.Process.Id)"
}

function Write-PeerLogs {
    param([Parameter(Mandatory = $true)] $Peer)
    Write-Host "`n--- $($Peer.Label) stdout ---"
    if (Test-Path $Peer.StdoutPath) {
        Get-Content -Raw $Peer.StdoutPath | Write-Host
    }
    Write-Host "--- $($Peer.Label) stderr ---"
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
        throw "Unexpected-host restart $($Peer.Label) emitted a Godot parser, runtime or native crash error."
    }
}

function Wait-ForPath {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [DateTime]$Deadline,
        [Parameter(Mandatory = $true)] [array]$ObservedPeers,
        [Parameter(Mandatory = $true)] [string]$Description
    )
    while (-not (Test-Path $Path) -and [DateTime]::UtcNow -lt $Deadline) {
        foreach ($peer in $ObservedPeers) {
            $peer.Process.Refresh()
            if ($peer.Process.HasExited -and -not (Test-Path $Path)) {
                Write-AllPeerLogs -Peers $ObservedPeers
                throw "$Description was not produced before $($peer.Label) exited."
            }
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path $Path)) {
        Write-AllPeerLogs -Peers $ObservedPeers
        throw "$Description was not produced before the bounded deadline."
    }
}

function Read-JsonEvidence {
    param(
        [Parameter(Mandatory = $true)] [string]$Label,
        [Parameter(Mandatory = $true)] [string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "Unexpected-host restart $Label evidence is missing: $Path"
    }
    $payload = Get-Content -Raw $Path | ConvertFrom-Json
    if ($null -eq $payload -or -not [bool]$payload.ok) {
        $message = if ($null -ne $payload) { [string]$payload.error } else { "invalid JSON evidence" }
        throw "Unexpected-host restart $Label failed: $message"
    }
    return $payload
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
    "epochbound-host-restart-" + [Guid]::NewGuid().ToString("N")
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

$port = 36000 + ($PID % 9000)
$host1ReadyPath = Join-Path $runRoot "host-1-ready.json"
$host1ExchangePath = Join-Path $runRoot "host-1-exchange.json"
$host1ReceiptPath = Join-Path $runRoot "host-1.json"
$allyInitialPath = Join-Path $runRoot "ally-initial.json"
$allyRecoveryPath = Join-Path $runRoot "ally-recovery.json"
$allyReceiptPath = Join-Path $runRoot "ally.json"
$host2StandbyPath = Join-Path $runRoot "host-2-standby.json"
$host2ActivationPath = Join-Path $runRoot "host-2-activate.txt"
$host2ReadyPath = Join-Path $runRoot "host-2-ready.json"
$host2ExchangePath = Join-Path $runRoot "host-2-exchange.json"
$host2ReceiptPath = Join-Path $runRoot "host-2.json"
$peers = @()

try {
    Write-Host "`n==> Smoke test automatic same-client recovery after forced ENet host-process loss on UDP $port"
    Write-Host "Isolated Godot user data: $isolatedUserRoot"

    $host1 = Start-RestartPeer `
        -Label "host-1" `
        -Role "host" `
        -Generation 1 `
        -Port $port `
        -ReceiptPath $host1ReceiptPath `
        -ReadyPath $host1ReadyPath `
        -ExchangePath $host1ExchangePath `
        -RunRoot $runRoot
    $peers += $host1
    Wait-ForPath `
        -Path $host1ReadyPath `
        -Deadline ([DateTime]::UtcNow.AddSeconds(20)) `
        -ObservedPeers @($host1) `
        -Description "Original host ready marker"

    $ally = Start-RestartPeer `
        -Label "ally" `
        -Role "ally" `
        -Port $port `
        -ReceiptPath $allyReceiptPath `
        -InitialPath $allyInitialPath `
        -RecoveryPath $allyRecoveryPath `
        -RunRoot $runRoot
    $peers += $ally

    $initialDeadline = [DateTime]::UtcNow.AddSeconds(30)
    Wait-ForPath `
        -Path $host1ExchangePath `
        -Deadline $initialDeadline `
        -ObservedPeers @($host1, $ally) `
        -Description "Original host authoritative exchange"
    Wait-ForPath `
        -Path $allyInitialPath `
        -Deadline $initialDeadline `
        -ObservedPeers @($host1, $ally) `
        -Description "Ally initial snapshot and input exchange"

    $host1Exchange = Read-JsonEvidence -Label "host generation 1" -Path $host1ExchangePath
    $allyInitial = Read-JsonEvidence -Label "ally initial" -Path $allyInitialPath
    if (
        [int]$host1Exchange.generation -ne 1 -or
        [int]$host1Exchange.ally_peer_id -le 1 -or
        [int]$host1Exchange.ally_input_sequence -le 20000 -or
        [int]$allyInitial.explicit_join_calls -ne 1 -or
        [int]$allyInitial.first_peer_id -ne [int]$host1Exchange.ally_peer_id -or
        [int]$allyInitial.first_snapshot_sequence -lt 0 -or
        [int]$allyInitial.first_input_sequence -le 20000
    ) {
        throw "Initial host and ally evidence did not prove one explicit join, production input and an authoritative snapshot."
    }

    # Prewarm the replacement Godot process while generation one remains
    # authoritative. Generation two loads the canonical runtime and waits in a
    # file-gated standby state without binding the shared UDP endpoint.
    $host2 = Start-RestartPeer `
        -Label "host-2" `
        -Role "host" `
        -Generation 2 `
        -Port $port `
        -ReceiptPath $host2ReceiptPath `
        -ReadyPath $host2ReadyPath `
        -ExchangePath $host2ExchangePath `
        -StandbyPath $host2StandbyPath `
        -ActivationPath $host2ActivationPath `
        -RunRoot $runRoot
    $peers += $host2
    Wait-ForPath `
        -Path $host2StandbyPath `
        -Deadline ([DateTime]::UtcNow.AddSeconds(20)) `
        -ObservedPeers @($host1, $host2, $ally) `
        -Description "Replacement host standby marker"
    $host2Standby = Read-JsonEvidence -Label "replacement host standby" -Path $host2StandbyPath
    $host2.Process.Refresh()
    $host1.Process.Refresh()
    if (
        [int]$host2Standby.generation -ne 2 -or
        [int]$host2Standby.port -ne $port -or
        [bool]$host2Standby.transport_bound -or
        (Test-Path $host2ReadyPath) -or
        $host2.Process.HasExited -or
        $host1.Process.HasExited
    ) {
        throw "Prewarmed replacement host must remain alive and unbound while generation one is authoritative."
    }
    Write-Host "HOST RESTART REPLACEMENT PREWARMED WITHOUT UDP BIND: pid $($host2.Process.Id)"

    # This is the fault boundary under test: terminate the original server
    # process directly, without invoking request_graceful_host_shutdown or any
    # other production lifecycle method.
    Force-Terminate-OriginalHost -Peer $host1
    Assert-PeerLogClean $host1

    Wait-ForPath `
        -Path $allyRecoveryPath `
        -Deadline ([DateTime]::UtcNow.AddSeconds(20)) `
        -ObservedPeers @($host2, $ally) `
        -Description "Ally bounded host-restart recovery state"
    $allyRecovery = Read-JsonEvidence -Label "ally recovery" -Path $allyRecoveryPath
    if (
        [int]$allyRecovery.explicit_join_calls -ne 1 -or
        [string]$allyRecovery.address -ne "127.0.0.1" -or
        [int]$allyRecovery.port -ne $port -or
        [string]$allyRecovery.role -ne "ally" -or
        [int]$allyRecovery.attempt_count -lt 0 -or
        [int]$allyRecovery.attempt_count -gt 6
    ) {
        throw "Ally recovery evidence did not preserve the exact accepted direct endpoint and role."
    }

    # Give the production backoff state enough time to begin its first internal
    # retry while the prewarmed replacement still has not bound the endpoint.
    Start-Sleep -Milliseconds 550
    if (Test-Path $host2ReadyPath) {
        throw "Replacement host bound its UDP endpoint before explicit fault activation."
    }
    Set-Content -Path $host2ActivationPath -Value "activate" -NoNewline -Encoding utf8
    Write-Host "HOST RESTART REPLACEMENT ACTIVATION RELEASED AFTER RECOVERY BEGAN"

    Wait-ForPath `
        -Path $host2ReadyPath `
        -Deadline ([DateTime]::UtcNow.AddSeconds(20)) `
        -ObservedPeers @($host2, $ally) `
        -Description "Replacement host ready marker"

    $completionDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (
        (-not (Test-Path $host2ReceiptPath) -or -not (Test-Path $allyReceiptPath)) -and
        [DateTime]::UtcNow -lt $completionDeadline
    ) {
        foreach ($peer in @($host2, $ally)) {
            $peer.Process.Refresh()
            if ($peer.Process.HasExited -and -not (Test-Path $peer.ReceiptPath)) {
                Write-AllPeerLogs -Peers $peers
                throw "$($peer.Label) exited before producing final host-restart evidence."
            }
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path $host2ReceiptPath) -or -not (Test-Path $allyReceiptPath)) {
        Write-AllPeerLogs -Peers $peers
        throw "Unexpected-host restart gate did not produce replacement-host and ally receipts within $TimeoutSeconds seconds."
    }

    $exitDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $exitDeadline) {
        $host2.Process.Refresh()
        $ally.Process.Refresh()
        if ($host2.Process.HasExited -and $ally.Process.HasExited) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    $host2.Process.Refresh()
    $ally.Process.Refresh()
    if (-not $host2.Process.HasExited -or -not $ally.Process.HasExited) {
        Write-AllPeerLogs -Peers $peers
        throw "Recovered host and ally did not complete independent graceful shutdown within 15 seconds."
    }

    Write-AllPeerLogs -Peers $peers
    foreach ($peer in @($host2, $ally)) {
        if ([int]$peer.Process.ExitCode -ne 0) {
            throw "$($peer.Label) exited with code $($peer.Process.ExitCode)."
        }
        Assert-PeerLogClean $peer
    }

    $host2Receipt = Read-JsonEvidence -Label "replacement host" -Path $host2ReceiptPath
    $allyReceipt = Read-JsonEvidence -Label "recovered ally" -Path $allyReceiptPath

    if (
        [int]$host2Receipt.generation -ne 2 -or
        [int]$host2Receipt.peer_count -ne 2 -or
        [int]$host2Receipt.ally_peer_id -le 1 -or
        [int]$host2Receipt.ally_peer_id -ne [int]$allyReceipt.local_peer_id -or
        [int]$host2Receipt.ally_input_sequence -le [int]$allyInitial.first_input_sequence -or
        [int]$host2Receipt.snapshot_sequence -lt 0 -or
        [int]$host2Receipt.snapshot_wire_bytes -le 0 -or
        [int]$host2Receipt.snapshot_wire_bytes -gt 1200 -or
        [int]$host2Receipt.snapshot_uncompressed_bytes -le [int]$host2Receipt.snapshot_wire_bytes -or
        [string]$host2Receipt.map_id -ne "clockwood_edge" -or
        [string]$host2Receipt.era_id -ne "ashen" -or
        [string]$host2Receipt.area_id -ne "clockwood_ashen_hunt" -or
        [int]$host2Receipt.host_shutdown_sequence -le 0 -or
        [int]$host2Receipt.host_shutdown_expected_count -ne 1 -or
        [int]$host2Receipt.host_shutdown_ack_count -ne 1 -or
        [int]$host2Receipt.host_shutdown_disconnect_count -ne 1 -or
        [bool]$host2Receipt.host_shutdown_forced -or
        [string]$host2Receipt.host_shutdown_reason -ne "HOST RESTART RECOVERY COMPLETE" -or
        [string]$host2Receipt.final_mode -ne "offline" -or
        -not [bool]$host2Receipt.independent_exit
    ) {
        throw "Replacement-host receipt did not prove recovered production input, bounded snapshot transport and acknowledged shutdown."
    }

    if (
        [int]$allyReceipt.explicit_join_calls -ne 1 -or
        [int]$allyReceipt.first_peer_id -ne [int]$allyInitial.first_peer_id -or
        [int]$allyReceipt.first_snapshot_sequence -ne [int]$allyInitial.first_snapshot_sequence -or
        [int]$allyReceipt.first_input_sequence -ne [int]$allyInitial.first_input_sequence -or
        [int]$allyReceipt.local_peer_id -le 1 -or
        [string]$allyReceipt.local_role -ne "ally" -or
        [int]$allyReceipt.peer_count -ne 2 -or
        [int]$allyReceipt.snapshot_sequence -lt 0 -or
        [int]$allyReceipt.input_sequence_sent -le [int]$allyReceipt.first_input_sequence -or
        [string]$allyReceipt.map_id -ne "clockwood_edge" -or
        [string]$allyReceipt.era_id -ne "ashen" -or
        [int]$allyReceipt.host_restart_generation -ne 1 -or
        [int]$allyReceipt.host_restart_attempt_count -lt 1 -or
        [int]$allyReceipt.host_restart_attempt_count -gt 6 -or
        -not [bool]$allyReceipt.host_restart_recovered -or
        [bool]$allyReceipt.host_restart_exhausted -or
        [string]$allyReceipt.host_restart_reason -ne "HOST RESTART RECOVERED" -or
        [string]$allyReceipt.host_restart_address -ne "127.0.0.1" -or
        [int]$allyReceipt.host_restart_port -ne $port -or
        [string]$allyReceipt.host_restart_role -ne "ally" -or
        -not [bool]$allyReceipt.manual_save_blocked_after_recovery -or
        -not [bool]$allyReceipt.autosave_blocked_after_recovery -or
        [int]$allyReceipt.host_shutdown_sequence -ne [int]$host2Receipt.host_shutdown_sequence -or
        [int]$allyReceipt.host_shutdown_ack_sent_sequence -ne [int]$host2Receipt.host_shutdown_sequence -or
        -not [bool]$allyReceipt.host_shutdown_commit_received -or
        -not [bool]$allyReceipt.host_shutdown_disconnect_observed -or
        [string]$allyReceipt.host_shutdown_reason -ne "HOST RESTART RECOVERY COMPLETE" -or
        [string]$allyReceipt.final_mode -ne "offline" -or
        -not [bool]$allyReceipt.independent_exit
    ) {
        throw "Ally receipt did not prove one explicit join, automatic same-process host recovery and final acknowledged shutdown."
    }

    Write-Host (
        "Unexpected-host restart recovery passed: the first ENet host was force-terminated without a close commit; " +
        "the same ally process retained the exact direct endpoint and role, used one of six bounded internal attempts, " +
        "joined a replacement host on the same UDP port without a second driver join call, sent later production input, " +
        "received a fresh authoritative snapshot, acknowledged the replacement host shutdown, and exited independently."
    )
}
finally {
    foreach ($peer in $peers) {
        Stop-RestartPeer $peer
    }
    foreach ($key in $environmentKeys) {
        Restore-EnvironmentValue -Snapshot $environmentSnapshot -Name $key
    }
    if (Test-Path $runRoot) {
        Remove-Item -Recurse -Force $runRoot -ErrorAction SilentlyContinue
    }
}

# Forced process termination is the intended fault injection for generation 1
# and is retained only as bounded failure cleanup for the surviving processes.
