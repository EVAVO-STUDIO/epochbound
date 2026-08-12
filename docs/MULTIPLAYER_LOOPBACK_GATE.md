# Real ENet Loopback, Reconnect and Host Shutdown Validation Gate

Epochbound’s in-process regressions validate host authority, authored co-op and PvP rules, save isolation and deterministic simulation. This gate adds transport evidence: three independent Godot processes communicate through real ENet UDP sockets on the loopback interface.

The gate launches one host, one co-op ally and one invader. Every process loads the canonical playable scene from `res://src/app.tscn`; none uses synthetic peer registration or a test-only multiplayer mode.

The host enters `clockwood_ashen_hunt` in Clockwood Edge’s Ashen era and opens a real ENet server on a bounded high UDP port. The ally and invader connect to `127.0.0.1` through the production `join_session` path, including the normal campaign-version, protocol-version, role-capacity and authored-area checks.

## Initial live exchange

After each accepted join, the drivers send bounded input retries through the production `_submit_input` RPC every 200 milliseconds. This avoids idle-frame timing assumptions while retaining the real unreliable-ordered input channel and validation path. The host receipt cannot complete until remote input reaches host authority for both remote roles.

The gate proves that authoritative snapshots reach both clients before the recovery phase begins. Each client must restore the expected map, era, role and three-actor party from a fresh snapshot. Receipts are written atomically through a temporary file and promotion, so the parent cannot observe partially written evidence.

## Bounded authenticated snapshots

The canonical multiplayer node uses `res://src/multiplayer_transport_session.gd`. It extends the host-authoritative session without changing progression or save ownership.

World snapshots use object-free Variant serialisation, Deflate compression and a hard **1,200-byte** wire budget. Each packet contains an `EPB1` magic prefix and a SHA-256 wire envelope over the compressed bytes. A client rejects bad magic, bad length or a digest mismatch before decompression. Decoding is capped at 65,536 bytes and never enables network-driven object construction.

The host sends the bounded payload only to connected peers that remain registered in authoritative state. Same-frame snapshot requests are coalesced and deferred so reliable join acceptance is queued first. Runtime entity facing stays within the authored `up`, `left`, `right` and `down` contract.

## Host-acknowledged graceful leave

A voluntary client leave uses a reliable protocol exchange rather than closing locally before the host sees the request.

The client sends `_request_graceful_leave` with a positive monotonic sequence and bounded reason. The host verifies that the remote sender is a registered peer, records bounded diagnostic history, removes the actor from authoritative simulation and returns `_graceful_leave_accepted` to that exact peer. The client accepts only the matching sequence and local peer ID.

While the leave is pending, the client stops sending gameplay input and stops applying world snapshots. After the acknowledgement, it detaches the high-level `MultiplayerAPI`, closes the old ENet peer and returns to a clean offline state. A three-second fallback performs local cleanup if a broken host never acknowledges.

The normal **Leave Online Session** action takes this path for connected clients. Join rejection, connection failure, server loss and host-forced removal remain immediate cleanup paths and do not attempt another exchange.

## Same-process reconnect

The ally records its first peer ID, first snapshot sequence and first production input sequence. It then completes the host-acknowledged graceful leave and waits until the local session is offline.

After a bounded settle interval, the same Godot process reconnects through the production `join_session` path. It must negotiate the ally role again, receive a later authoritative snapshot and send a later production input sequence. The proof does not assume that a transport implementation must allocate a numerically different peer ID; the evidence is the acknowledged leave, offline transition, second join and second authoritative exchange.

The host must simultaneously prove that:

- the graceful-leave request referred to the original ally;
- exactly one ally and one invader are registered again;
- both current remote actors have fresh host-authoritative input;
- the original invader remains connected throughout the ally cycle;
- the final snapshot contains the restored party, expected map, era and PvP area.

## All-map snapshot matrix

A separate focused regression covers all eight reference map/era states:

```text
Bellweather Crossing / Verdant
Bellweather Crossing / Ashen
Clockwood Edge / Verdant
Clockwood Edge / Ashen
Museum Underworks / Verdant
Museum Underworks / Ashen
```

Co-op and sanctuary cases use the host plus two allies. Clockwood’s Ashen PvP case uses the host, two allies and one invader. Every state must encode below 1,200 bytes, decode to the same map and era and preserve the complete allowed party.

The matrix also rejects oversized packets, malformed headers, digest mismatches and deterministic incompressible state that cannot fit the transport budget. Those failures occur before unsafe decompression or runtime mutation.

## Receipt requirements

The host receipt proves current party counts, both current input streams, the original graceful-leave peer, the persistent invader, protocol version, map, era, authored area, bounded final snapshot, positive shutdown sequence, two expected peers, two unique acknowledgements, non-forced commit and final offline state.

The ally receipt proves the first join, first input and snapshot, positive leave acknowledgement, same-process reconnect generation, later input and later snapshot. The invader receipt proves that its original transport remains alive while the ally leaves and rejoins. Both client receipts prove they acknowledged the host sequence, received the matching commit, returned offline and exited independently.

The harness is:

```text
scripts/validate_multiplayer_loopback.ps1
```

It creates isolated Godot user-data roots, readiness markers, logs and receipts under one unique operating-system temporary directory. It applies bounded startup and completion deadlines, rejects early child exit, and scans all child output for parser, runtime and native crash errors.

The ally itself exercises a real client detach, close and reconnect. After the second exchange, the host refuses new connections, sends one reliable shutdown request to every registered remote peer, waits for unique acknowledgements, sends a reliable commit, and closes only after the clients detach or a bounded commit grace expires.

Each client stops input and snapshot application as soon as the host request arrives, acknowledges the exact sequence, accepts only the matching commit, detaches its high-level `MultiplayerAPI`, closes ENet and returns offline. The host records expected and acknowledged counts and fails the gate if shutdown required its timeout fallback.

All three peers atomically publish final receipts, release the canonical runtime through the shared Audio-aware headless cleanup contract, and exit independently with code zero. The parent harness waits for those exits and keeps forced process-tree termination only for failure cleanup.

## Permanent fail-closed contract

Before Godot starts, the governed workflow runs:

```text
python3 tools/check_multiplayer_loopback_contract.py
```

The checker rejects drift that removes real socket use, production input RPCs, the acknowledged leave sequence, same-process reconnect, persistent-invader evidence, bounded snapshot security, atomic receipts, clean-source checks or production workflow integration.

The multiplayer compile probe loads the production transport, both loopback drivers and the snapshot-matrix regression, so parser and inheritance drift fail before process orchestration.

The exact-main validation receipt records:

```json
{
  "multiplayerLoopbackValidation": "passed"
}
```

That field means the static contract, six-state matrix, initial real exchange, host-acknowledged client leave, same-process reconnect, persistent invader, second input/snapshot exchange, acknowledged host shutdown, independent process exit, log review and clean-source verification all passed.

The exact-main receipt also records:

```json
{
  "multiplayerHostShutdownValidation": "passed"
}
```

## Remaining boundaries

This gate proves graceful client leave, bounded same-process reconnect, acknowledged host shutdown and independent final process exit. Unexpected-host restart recovery is covered by the dedicated [`MULTIPLAYER_HOST_RESTART_RECOVERY.md`](MULTIPLAYER_HOST_RESTART_RECOVERY.md) real-process gate. This loopback gate does not prove host migration, latency or packet-loss tolerance, relay behaviour, NAT traversal, platform invitations, mobile permissions, anti-cheat or moderation.

It does not prove public Internet reachability merely because loopback succeeds. Those boundaries require dedicated lifecycle, multi-machine and network-condition validation.

### Host-directed disconnect ordering

After every registered client acknowledges the shutdown request, the host broadcasts one reliable commit and keeps the ENet server alive for a bounded flush window. Clients become quiescent but remain connected. The host then disconnects each captured peer, waits for those disconnects to be observed or for the bounded disconnect grace to expire, and only then closes the server. This prevents a client-side close from racing a later high-level send and proves that all peers return offline without harness-forced termination.

The final real-socket phase proves a host-directed disconnect after every captured peer acknowledges the same shutdown sequence.

- Host teardown uses a SceneMultiplayer-owned disconnect for every acknowledged peer, clearing relay membership before ENet channel shutdown and preventing zero-channel sends.
