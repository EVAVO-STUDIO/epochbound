# Real ENet Loopback Validation Gate

Epochbound’s multiplayer model and runtime regressions validate host authority, authored co-op and PvP rules, snapshot bounds and save isolation inside one Godot process. This gate adds the missing transport-level proof: three independent Godot processes communicate through real ENet UDP sockets on the loopback interface.

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

After the real join is accepted, each client driver sends bounded input retries through the production `_submit_input` RPC every 200 milliseconds until the host records a fresh monotonic sequence. This removes dependence on idle-frame timing while preserving the actual unreliable-ordered input channel and host validation path.

The driver does not create peers, inject peer state or call test-only registration helpers. The host receipt succeeds only after it records one real ally input stream and one real invader input stream.

Client receipts are promoted atomically from temporary files, so the parent harness cannot mistake a partially written record for complete evidence.

## Bounded snapshot transport

The canonical `MultiplayerSession` uses `res://src/multiplayer_transport_session.gd`, which extends the host-authoritative base session without changing progression or save ownership.

Authoritative world snapshots use object-free Variant serialisation, Deflate compression and a hard **1,200-byte** compressed wire budget. Decoding is capped at 65,536 bytes and does not enable object construction from network data.

The host sends the compressed payload separately to each currently connected, registered peer. Snapshot requests in the same frame are coalesced and deferred so reliable role acceptance is queued before the first world snapshot.

Runtime entity facing remains a bounded cardinal name on the wire. This preserves the inherited renderer’s authored `up`, `left`, `right` and `down` contract instead of introducing incompatible vector values on clients.

## What must be proven

The host receipt must prove:

- exactly one host, one ally and one invader are registered;
- both remote peers sent monotonic input through the production unreliable-ordered input channel;
- remote input reaches host authority;
- the host built a protocol-versioned authoritative snapshot;
- the compressed snapshot is greater than zero and no larger than 1,200 bytes;
- the uncompressed snapshot is larger than the compressed payload;
- the active map, era and PvP area are the expected authored records.

Each client receipt must prove:

- the connection completed as the requested role;
- the server assigned a real peer ID greater than one;
- at least one bounded production input RPC was sent;
- the client received a fresh authoritative snapshot;
- authoritative snapshots reach both clients;
- the snapshot restored all three transient actors;
- the host map and era were applied through the production snapshot path.

## Bounded orchestration

The harness is:

```text
scripts/validate_multiplayer_loopback.ps1
```

It uses a unique operating-system temporary directory for readiness markers, receipts and logs. It derives a bounded high UDP port from the parent validation process, waits for host readiness, staggers ally and invader startup, applies hard timeouts and rejects any child that exits or logs a parser, runtime or native crash before producing evidence.

After all three flushed receipts are present, the harness verifies that all processes are still alive, validates every receipt and log, then the parent harness owns process termination and removes all temporary files in `finally` cleanup. Tracked repository source is never used for receipts or coordination.

This division is deliberate: the gate validates the live transport exchange and does not validate graceful disconnect or Godot’s independent headless process-exit lifecycle. Those require a separate test boundary rather than being inferred from successful UDP communication.

## Permanent source contract

Before Godot starts, the exact-main workflow runs:

```text
python3 tools/check_multiplayer_loopback_contract.py
```

The checker rejects drift that would replace the real socket exchange with synthetic peer registration, remove host or client receipts, stop checking bounded input retries, stop checking authoritative snapshots, remove the 1,200-byte budget, enable object decoding, remove bounded cleanup or detach the gate from the production workflow.

The multiplayer compile probe also loads:

```text
res://src/multiplayer_transport_session.gd
res://tools/multiplayer_loopback_peer.gd
res://tools/multiplayer_loopback_peer_driver.gd
```

so parser or inheritance drift fails before process orchestration begins.

## Validation receipt

The governed exact-main receipt records:

```json
{
  "multiplayerLoopbackValidation": "passed"
}
```

A release is not considered multiplayer-transport validated if the static contract, real loopback process exchange, bounded input and snapshot evidence, child-log review, clean-source verification or receipt field is absent.

## What this gate does not prove

Loopback proves that the production ENet server, client, RPC, input-channel and snapshot-channel paths work between independent processes on one machine. It does not prove public Internet reachability, router configuration, relay behaviour, NAT traversal, platform invitations, mobile permissions, graceful disconnect, host migration, reconnect policy, latency tolerance, packet-loss tolerance, anti-cheat or moderation.

Those remain separate production boundaries and require real multi-machine and network-condition testing.
