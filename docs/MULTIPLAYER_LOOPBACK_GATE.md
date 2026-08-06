# Real ENet Loopback Validation Gate

Epochbound’s multiplayer model and runtime regressions validate host authority, authored co-op and PvP rules, snapshot bounds and save isolation inside one Godot process. This gate adds the missing transport-level proof: three independent Godot processes communicate through real ENet UDP sockets on the loopback interface.

The gate now also proves one complete recovery cycle. The ally completes an initial authoritative exchange, performs a host-acknowledged graceful leave, closes its first ENet client, reconnects from the same Godot process and resumes production input and snapshot flow while the original invader remains connected.

## What the gate launches

The PowerShell harness starts:

```text
one host process
one co-op ally process
one invader process
```

Each process loads the canonical playable scene from `res://src/app.tscn`. No synthetic peer registration or test-only session mode is used.

The host enters the authored `clockwood_ashen_hunt` region in Clockwood Edge’s Ashen era, opens a real ENet server on a bounded high UDP port and writes a readiness marker outside the repository.

The ally and invader then connect to `127.0.0.1` through the production `join_session` path. They use the same campaign-version negotiation, role-capacity checks and reliable join RPCs as a normal game session.

## Deterministic input evidence

After each real join is accepted, the client driver sends bounded input retries through the production `_submit_input` RPC every 200 milliseconds until the host records a fresh monotonic sequence. This removes dependence on idle-frame timing while preserving the actual unreliable-ordered input channel and host validation path.

The initial phase is held for a bounded interval after the complete snapshot arrives, allowing repeated input evidence to reach host authority before the ally requests leave. The reconnect phase repeats that evidence after a fresh join and fresh authoritative snapshot.

The driver does not create peers, inject peer state or call test-only registration helpers. The host receipt succeeds only after it records one current ally input stream and one persistent invader input stream following the ally’s acknowledged leave and reconnect.

Client receipts are promoted atomically from temporary files, so the parent harness cannot mistake a partially written record for complete evidence.

## Bounded snapshot transport

The canonical `MultiplayerSession` uses `res://src/multiplayer_transport_session.gd`, which extends the host-authoritative base session without changing progression or save ownership.

Authoritative world snapshots use object-free Variant serialisation, Deflate compression and a hard **1,200-byte** compressed wire budget. Every payload has an `EPB1` magic prefix and a SHA-256 wire envelope over the compressed bytes. Clients reject the wrong magic, wrong length or checksum mismatch before decompression. Decoding is capped at 65,536 bytes and does not enable object construction from network data.

The host sends the compressed payload separately to each currently connected, registered peer. Snapshot requests in the same frame are coalesced and deferred so reliable role acceptance is queued before the first world snapshot.

Runtime entity facing remains a bounded cardinal name on the wire. This preserves the inherited renderer’s authored `up`, `left`, `right` and `down` contract instead of introducing incompatible vector values on clients.

## Host-acknowledged graceful leave

A voluntary client leave no longer depends on closing the local socket before the host has observed the request.

The client sends a reliable `_request_graceful_leave` RPC carrying a positive monotonic sequence and a bounded reason. The host validates the remote sender against the registered peer set, records bounded diagnostic history, removes that actor from authoritative simulation and returns `_graceful_leave_accepted` to that exact peer. Only the matching client sequence and peer ID can complete the acknowledgement.

After the acknowledgement arrives, the client detaches the high-level `MultiplayerAPI`, closes the old ENet peer and returns to an isolated offline state. During the pending leave window, client input and snapshot application stop. A three-second fallback closes locally if a broken host never acknowledges, so the user cannot remain trapped in a pending state.

The normal in-game **Leave Online Session** action uses this acknowledged path for connected clients. Connection failures, host-forced removals, join rejection and server loss remain immediate cleanup paths and do not attempt a second protocol exchange.

## Same-process reconnect proof

The ally’s driver records its first peer ID, first authoritative snapshot sequence and first production input sequence. It then requests the graceful leave and waits until the matching acknowledgement has returned and the session is offline.

After a bounded settle interval, the same Godot process calls the production `join_session` path again. It must negotiate the ally role again, receive a new authoritative snapshot and send a later production input sequence. The host must simultaneously prove:

- the acknowledged leave request referred to the original ally peer;
- exactly one ally and one invader are present again;
- both current remote actors have fresh input recorded by host authority;
- the original invader remains connected throughout the ally cycle;
- the final bounded snapshot contains the restored party, expected map, era and authored PvP area.

The reconnect proof does not assume that a transport implementation must allocate a numerically different peer ID. It proves a completed leave acknowledgement, offline transition, second production join and second authoritative exchange in one process.

## All-map snapshot matrix

A focused regression builds maximum authored parties across all six reference map/era states:

```text
Bellweather Crossing / Verdant
Bellweather Crossing / Ashen
Clockwood Edge / Verdant
Clockwood Edge / Ashen
Museum Underworks / Verdant
Museum Underworks / Ashen
```

Co-op and sanctuary cases use the host plus two allies. Clockwood’s Ashen PvP case uses the host, two allies and one invader. Every state must encode, remain below 1,200 bytes, decode to the same map and era and preserve the complete allowed party.

The matrix also rejects oversized payloads, bad wire magic, checksum mismatches and deterministic incompressible state that exceeds the transport budget. These failures must occur before unsafe decompression or runtime mutation.

## What must be proven

The host receipt must prove:

- exactly one host, one ally and one invader are registered after reconnect;
- both current remote peers sent monotonic input through the production unreliable-ordered input channel;
- remote input reaches host authority;
- at least one valid graceful-leave request was accepted for the original ally;
- the persistent invader peer remains the same actor during the ally cycle;
- the host built a protocol-versioned authoritative snapshot after reconnect;
- the compressed snapshot is greater than zero and no larger than 1,200 bytes;
- the uncompressed snapshot is larger than the compressed payload;
- the active map, era and PvP area are the expected authored records.

The ally receipt must additionally prove:

- the first connection completed as the ally role;
- the first connection received an authoritative snapshot and sent bounded production input;
- the host returned the matching positive graceful-leave acknowledgement;
- the session became offline before the second join began;
- the same Godot process reconnects through the production join path;
- the second connection receives a later authoritative snapshot and sends a later input sequence;
- the final map, era, role and complete party are restored.

The invader receipt must prove its original connection remains alive and authoritative while the ally leaves and rejoins.

## Bounded orchestration

The harness is:

```text
scripts/validate_multiplayer_loopback.ps1
```

It uses a unique operating-system temporary directory for readiness markers, receipts and logs. It derives a bounded high UDP port from the parent validation process, waits for host readiness, staggers ally and invader startup, applies hard timeouts and rejects any child that exits or logs a parser, runtime or native crash before producing evidence.

After all three flushed receipts are present, the harness verifies that all processes are still alive, validates every receipt and log, then the parent harness owns final process termination and removes all temporary files in `finally` cleanup. Tracked repository source is never used for receipts or coordination.

This division is deliberate. The ally itself has already exercised real client detach, ENet close and reconnect. The parent owns only the final termination of the three headless validation processes, so final process teardown is not confused with transport recovery evidence.

## Permanent source contract

Before Godot starts, the exact-main workflow runs:

```text
python3 tools/check_multiplayer_loopback_contract.py
```

The checker rejects drift that would replace the real socket exchange with synthetic peer registration, remove host or client receipts, stop checking bounded input retries, stop checking the acknowledged leave sequence, stop checking same-process reconnect, stop checking the persistent invader, stop checking authoritative snapshots, remove the SHA-256 envelope or 1,200-byte budget, enable object decoding, remove bounded cleanup or detach the gate from the production workflow.

The multiplayer compile probe also loads:

```text
res://src/multiplayer_transport_session.gd
res://tools/multiplayer_loopback_peer.gd
res://tools/multiplayer_loopback_peer_driver.gd
res://tools/smoke_multiplayer_snapshot_transport.gd
```

so parser or inheritance drift fails before process orchestration begins.

## Validation receipt

The governed exact-main receipt records:

```json
{
  "multiplayerLoopbackValidation": "passed"
}
```

The meaning of this field includes the static transport contract, all-map matrix, initial live exchange, acknowledged ally leave, same-process reconnect, persistent-invader evidence, second input and snapshot exchange, child-log review and clean-source verification.

A release is not considered multiplayer-transport validated if any of those boundaries or the receipt field is absent.

## What this gate does not prove

Loopback proves that the production ENet server, client, RPC, input-channel and snapshot-channel paths work between independent processes on one machine. It proves graceful client leave and a bounded same-process client reconnect against a still-running host.

It does not prove graceful host shutdown, independent headless process exit, host migration, automatic reconnect after an unexpected outage, reconnect across a restarted host, public Internet reachability, router configuration, relay behaviour, NAT traversal, platform invitations, mobile permissions, latency tolerance, packet-loss tolerance, anti-cheat or moderation.

Those remain separate production boundaries and require dedicated lifecycle, multi-machine and network-condition testing. The gate does not prove public Internet reachability merely because loopback transport succeeds.