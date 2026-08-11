# Unexpected Host Restart Recovery

Epochbound treats intentional host shutdown and unexpected host-process loss as different lifecycle events. The acknowledged shutdown protocol remains the preferred clean exit. This recovery path exists only when an already accepted direct ENet client loses the host without receiving a committed shutdown sequence.

## Recovery eligibility

Automatic recovery is armed only after the production client has successfully joined through a literal IPv4 or IPv6 endpoint. The runtime preserves the exact accepted address, UDP port, player role and sanitized local player name in transient player-local memory.

Hostnames are deliberately excluded. Automatically resolving a hostname again could send the client to a different machine after DNS changes. Connection details are not written into campaign saves, packages, snapshots or shared campaign data.

Intentional client leave, join rejection, explicit cancellation and acknowledged graceful host shutdown never start host restart recovery.

## Bounded state machine

Unexpected host-process loss detaches the stale ENet peer and enters an offline backoff state. Manual saves and autosaves remain blocked throughout that pending recovery. After a successful reconnect, the recovery-specific block ends but the normal connected-client save isolation remains active until the online session closes. Cancellation or exhaustion returns the player offline and removes the recovery block.

The retry policy is deterministic:

- six attempts;
- 0.35 seconds before the first attempt;
- exponential delays of 0.70 and 1.40 seconds;
- a hard cap of 2.0 seconds for later attempts;
- no wall-clock persistence, random jitter or offline progress.

A retry replays only the exact production `join_session` callable with the accepted direct endpoint, port, role and player name. Duplicate stale disconnect callbacks from disposal of the old peer cannot consume an attempt or reset an in-flight timer.

Godot disconnect signals are notification-only. They queue one idempotent deferred transition, and only after `MultiplayerAPI` has finished native signal dispatch does the runtime detach and close the stale ENet peer. Duplicate `server_disconnected`, host `peer_disconnected` and `connection_failed` notifications collapse into that same handoff instead of freeing transport state from inside the callback.

Successful join acceptance increments a monotonic recovery generation and records the successful attempt count. Exhaustion returns the player offline and requires a new explicit Online Play request. Escape, Pause or the Online Play control can cancel pending recovery.

## Real process validation

The governed gate is:

```text
scripts/validate_multiplayer_host_restart.ps1
```

It launches an original host and one ally through real ENet UDP sockets. The ally performs one explicit production join, sends production input and receives an authoritative snapshot. The parent harness then uses forced process termination on the original host without invoking any graceful shutdown method.

The gate prewarms the replacement Godot process while the original host remains authoritative. Generation two loads the canonical runtime and publishes a standby marker, but it does not bind the shared UDP endpoint. This separates process startup time from the production retry budget without allowing two hosts to own the same port.

The same client process must detect the outage, preserve the literal endpoint and ally role, and enter the bounded retry state. Only after the first backoff interval has elapsed does the harness publish an activation marker. The driver makes one explicit join for the original connection. The prewarmed replacement host then opens ENet on the original UDP port, and the client must join it without a second explicit driver join call.

During each pending `create_client` attempt, `connection_failed` is the authoritative failure signal. Late `server_disconnected` or server-peer `peer_disconnected` notifications from the disposed generation-one transport are ignored until the new transport is accepted. Once the client has joined generation two, a later server disconnect is again authoritative. This prevents stale native callbacks from consuming all six retries before the replacement host can answer.

After recovery, the replacement host must receive a later production input sequence and the ally must receive a fresh authoritative snapshot. The replacement host then performs the normal acknowledged graceful shutdown. Both surviving Godot processes publish atomic receipts, release the canonical runtime and exit independently with code zero.

The static contract is:

```text
python3 tools/check_multiplayer_host_restart_contract.py
```

The exact-main receipt records:

```json
{
  "multiplayerHostRestartRecoveryValidation": "passed"
}
```

## Explicit boundaries

This feature recovers a client when a replacement host process becomes available on the same literal endpoint. It does not provide host migration, election of a new host, transfer of host-owned durable progression, relay infrastructure, NAT traversal, public matchmaking, platform invitations, packet-loss simulation or public Internet reachability.

A clean host remains responsible for using the acknowledged shutdown protocol. Recovery is a bounded outage path, not a substitute for graceful lifecycle ownership.
