# Multiplayer Connection Release Contract

Epochbound’s in-game Connection Setup is a player-local configuration surface layered above the existing host-authoritative ENet session. It configures only the endpoint and local display name used for a future connection.

It does not change campaign state, host authority, RPC permissions, snapshot contents, party limits, PvP rules or durable progression ownership.

## Persistent location

Connection details are stored at:

```text
user://settings/multiplayer_connection.json
```

The profile contains only:

```text
schema_version
address
port
player_name
```

It is not part of:

```text
campaign JSON
campaign save profiles
portable campaign packages
network snapshots
host-owned progression
```

## Validation boundary

The model accepts bounded hostnames, direct IPv4 addresses and IPv6 addresses. Bracketed IPv6 input is normalised before use.

It rejects:

- URL schemes and paths;
- whitespace;
- a combined `address:port` value when the port has its own field;
- UDP ports below 1024 or above 65535;
- unsupported display-name characters;
- unknown future schemas.

Raw profile validation runs before sanitisation, temporary-file creation or backup rotation. Invalid form or API input cannot silently become defaults and replace a known-good profile.

## Atomic storage and recovery

A valid write follows this order:

1. Validate the raw profile.
2. Canonicalise the already-valid values.
3. Validate the canonical profile.
4. Write and flush a complete temporary file.
5. Rotate one valid primary profile to `.bak`.
6. Promote the temporary file.
7. Restore the backup if promotion fails.

Startup attempts the primary profile, then the backup, then safe localhost defaults. Backup recovery and invalid-primary fallback remain visible when the player opens the Online Play lobby.

## Input ownership

Connection Setup uses normal Godot `Control`, `LineEdit` and `SpinBox` focus behaviour. Keyboard, mouse, controller focus navigation and supported virtual keyboards use one bounded form.

While the form is open, lobby polling is suspended. Save and Back restore lobby polling on the next frame so a single Confirm or Cancel press cannot activate both interfaces.

## Command-line precedence

These launch arguments remain explicit higher-priority overrides:

```text
--host
--join=
--invade
--port=
--name=
```

They are retained for automation and multi-instance testing. A launch using any of these networking arguments does not replace its values with the saved in-game profile.

## Save and network isolation

The connection profile never enters `capture_save_profile`, campaign package manifests or authoritative world snapshots.

Permanent regressions reject connection fields in campaign saves and confirm that saved endpoint details update only the existing session configuration:

```text
connect_address
connect_port
local_name
multiplayer_connection_profile
```

## Permanent validation

The exact-main workflow runs:

```text
python3 tools/check_multiplayer_connection_contract.py
```

before downloading Godot. The checker pins:

- the connection model and schema;
- raw validation and atomic storage order;
- backup and localhost recovery;
- command-line precedence;
- canonical scene and runtime contract ownership;
- compile-probe coverage;
- the executable connection-profile regression;
- campaign save, package and snapshot isolation;
- the complete local gate;
- this documentation;
- the governed workflow and bounded receipt.

The complete Godot gate directly compiles and runs:

```text
res://tools/compile_multiplayer_probe.gd
res://tools/smoke_multiplayer_connection_profile.gd
```

The bounded validation receipt records:

```json
{
  "multiplayerConnectionValidation": "passed"
}
```

A release is not considered validated if the checker, compile probe, regression, clean-source verification or receipt field is absent.
