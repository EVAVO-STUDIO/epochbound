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

## What must be proven

The host receipt must prove:

- exactly one host, one ally and one invader are registered;
- both remote peers sent monotonic input through the production unreliable-ordered input channel;
- remote input reaches host authority;
- the host built a protocol-versioned authoritative snapshot;
- the active map, era and PvP area are the expected authored records.

Each client receipt must prove:

- the connection completed as the requested role;
- the server assigned a real peer ID greater than one;
- the client received a fresh authoritative snapshot;
- authoritative snapshots reach both clients;
- the snapshot restored all three transient actors;
- the host map and era were applied through the production snapshot path.

## Bounded orchestration

The harness is:

```text
scripts/validate_multiplayer_loopback.ps1
```

It uses a unique operating-system temporary directory for readiness markers, receipts and logs. It derives a bounded high UDP port from the parent validation process, waits for host readiness, applies hard timeouts, validates every child exit code and log, terminates remaining process trees on failure and removes all temporary files in `finally` cleanup.

Tracked repository source is never used for receipts or coordination.

## Permanent source contract

Before Godot starts, the exact-main workflow runs:

```text
python3 tools/check_multiplayer_loopback_contract.py
```

The checker rejects drift that would replace the real socket exchange with synthetic peer registration, remove host or client receipts, stop checking remote input, stop checking authoritative snapshots, remove bounded cleanup or detach the gate from the production workflow.

The multiplayer compile probe also loads:

```text
res://tools/multiplayer_loopback_peer.gd
```

so parser or inheritance drift fails before process orchestration begins.

## Validation receipt

The governed exact-main receipt records:

```json
{
  "multiplayerLoopbackValidation": "passed"
}
```

A release is not considered multiplayer-transport validated if the static contract, real loopback process exchange, child-log review, clean-source verification or receipt field is absent.

## What this gate does not prove

Loopback proves that the production ENet server, client, RPC, input-channel and snapshot-channel paths work between independent processes on one machine. It does not prove public Internet reachability, router configuration, relay behaviour, NAT traversal, platform invitations, mobile permissions, host migration, reconnect policy, latency tolerance, packet-loss tolerance, anti-cheat or moderation.

Those remain separate production boundaries and require real multi-machine and network-condition testing.
