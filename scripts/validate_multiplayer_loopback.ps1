param(
    [Parameter(Mandatory = $true)] [string]$GodotExecutable,
    [Parameter(Mandatory = $true)] [string]$ProjectRoot,
    [int]$TimeoutSeconds = 40
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
        "res://tools/multiplayer_loopback_peer.gd",
        "--",
        "--role=$Role",
        "--port=$Port",
        "--receipt=$ReceiptPath",
        "--timeout=24"
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
    if ($combined -match "SCRIPT ERROR:" -or $combined -match "(?m)^ERROR:") {
        throw "Real ENet loopback $($Peer.Role) emitted a Godot parser or runtime error."
    }
}

$runRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "epochbound-enet-loopback-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$port = 32000 + ($PID % 10000)
$readyPath = Join-Path $runRoot "host-ready.json"
$hostReceiptPath = Join-Path $runRoot "host.json"
$allyReceiptPath = Join-Path $runRoot "ally.json"
$invaderReceiptPath = Join-Path $runRoot "invader.json"
$peers = @()

try {
    Write-Host "`n==> Smoke test real ENet host ally and invader loopback on UDP $port"
    $hostPeer = Start-LoopbackPeer `
        -Role "host" `
        -Port $port `
        -ReceiptPath $hostReceiptPath `
        -ReadyPath $readyPath `
        -RunRoot $runRoot
    $peers += $hostPeer

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path $readyPath) -and [DateTime]::UtcNow -lt $readyDeadline) {
        $hostPeer.Process.Refresh()
        if ($hostPeer.Process.HasExited) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path $readyPath)) {
        Write-PeerLogs $hostPeer
        throw "Real ENet loopback host did not open its UDP listener."
    }

    $allyPeer = Start-LoopbackPeer `
        -Role "ally" `
        -Port $port `
        -ReceiptPath $allyReceiptPath `
        -ReadyPath $readyPath `
        -RunRoot $runRoot
    $peers += $allyPeer
    Start-Sleep -Milliseconds 350
    $invaderPeer = Start-LoopbackPeer `
        -Role "invader" `
        -Port $port `
        -ReceiptPath $invaderReceiptPath `
        -ReadyPath $readyPath `
        -RunRoot $runRoot
    $peers += $invaderPeer

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $allExited = $true
        foreach ($peer in $peers) {
            $peer.Process.Refresh()
            if (-not $peer.Process.HasExited) {
                $allExited = $false
            }
        }
        if ($allExited) {
            break
        }
        Start-Sleep -Milliseconds 100
    }

    foreach ($peer in $peers) {
        $peer.Process.Refresh()
        if (-not $peer.Process.HasExited) {
            throw "Real ENet loopback $($peer.Role) exceeded the $TimeoutSeconds-second harness timeout."
        }
        if ($peer.Process.ExitCode -ne 0) {
            Write-PeerLogs $peer
            throw "Real ENet loopback $($peer.Role) exited with code $($peer.Process.ExitCode)."
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
        [string]$hostReceipt.map_id -ne "clockwood_edge" -or
        [string]$hostReceipt.era_id -ne "ashen" -or
        [string]$hostReceipt.area_id -ne "clockwood_ashen_hunt"
    ) {
        throw "Real ENet loopback host receipt did not prove the complete authoritative exchange."
    }

    foreach ($receipt in @($allyReceipt, $invaderReceipt)) {
        $expectedRole = [string]$receipt.role
        if (
            [int]$receipt.local_peer_id -le 1 -or
            [string]$receipt.local_role -ne $expectedRole -or
            [int]$receipt.peer_count -ne 3 -or
            [int]$receipt.snapshot_sequence -lt 0 -or
            [string]$receipt.map_id -ne "clockwood_edge" -or
            [string]$receipt.era_id -ne "ashen"
        ) {
            throw "Real ENet loopback $expectedRole receipt did not prove authoritative snapshot restoration."
        }
    }

    foreach ($peer in $peers) {
        Write-PeerLogs $peer
    }
    Write-Host "Real ENet loopback passed: host, ally and invader negotiated through UDP, remote inputs reached host authority, and both clients restored authoritative snapshots."
}
finally {
    foreach ($peer in $peers) {
        Stop-LoopbackPeer $peer
    }
    if (Test-Path $runRoot) {
        Remove-Item -Recurse -Force $runRoot -ErrorAction SilentlyContinue
    }
}
