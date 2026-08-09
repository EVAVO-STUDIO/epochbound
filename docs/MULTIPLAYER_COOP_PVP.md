# Co-op, Invasions and Authored PvP Areas

Epochbound supports an original host-authoritative online layer alongside the complete offline journey.

The design keeps single-player as the durable foundation. Online guests join the host's current world as temporary actors:

- **Allies** help with exploration and enemy combat.
- **Invaders** are hostile only inside explicitly authored PvP areas.
- **The host** owns campaign progression, world state, inventory, economy and saves.

The implementation is inspired by the broad idea of asynchronous-risk action RPG multiplayer, but it does not copy another game's terminology, matchmaking, maps, interface, rules, rewards or network implementation.

## Current scope

The production vertical slice supports:

- one host;
- up to two co-op allies;
- up to one invader;
- direct-IP ENet sessions over UDP;
- in-game hostname, IPv4, IPv6, UDP-port and display-name setup;
- a versioned player-local connection profile with atomic writes and backup recovery;
- command-line networking overrides for automation and multi-instance testing;
- campaign-version and protocol matching;
- host-authoritative movement, enemy damage and PvP damage;
- unreliable-ordered input and snapshot channels;
- reliable role negotiation and disconnect messages;
- authored sanctuary, co-op and PvP areas;
- co-op friendly fire disabled by default;
- PvP grace after joining or respawning;
- temporary ally downing and respawning;
- temporary invader banishment;
- bounded peer snapshots without durable inventory or quest data;
- host-only progression and session-only PvP scores;
- manual-save locking while remote peers are present;
- autosave deferral while an invasion is active;
- offline, host and client modes in the same canonical scene;
- acknowledged host shutdown with bounded fallback and clean peer exit.

There is no central matchmaking, relay, account service, anti-cheat service, voice chat, platform invitation service or NAT traversal service in this slice. Internet hosts must expose the configured UDP port or use a future relay/invitation layer.

## Opening the online menu

The online menu uses fixed recovery inputs and is not part of the remappable gameplay profile:

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open or close Online Play | N | Guide |
| Select | Up / Down | D-pad Up / Down |
| Open Connection Setup | Right or Tab | D-pad Right or focus-next |
| Confirm | Active Interact binding | Confirm button |
| Back | Escape | Start |

The menu offers:

```text
HOST CO-OP
JOIN CO-OP
INVADE
BACK
```

When already online it offers **Leave Online Session** and **Back**.

The offline lobby shows the current connection address and UDP port. Press **Right** or **Tab** to open **Connection Setup** before hosting, joining or invading. The setup surface provides:

```text
hostname or IPv4 / IPv6 address
UDP port
online display name
Save Connection
Reset Localhost
Back
```

The address field accepts a hostname or a direct IPv4/IPv6 address. It rejects URL schemes, paths, whitespace and combined `address:port` input because the UDP port has its own bounded field. Bracketed IPv6 input such as `[::1]` is normalised to the address ENet consumes.

The display name accepts letters, numbers, spaces, underscores and hyphens up to the authored session-name limit. The UDP port must be between `1024` and `65535`.

Connection details are player-local and never enter campaign data, portable campaign packages or save-profile payloads. They are stored separately at:

```text
user://settings/multiplayer_connection.json
```

Writes use a temporary file, rotate one valid previous profile to `.bak`, and recover from that backup when the primary JSON is malformed or unavailable. **Reset Localhost** restores `127.0.0.1`, the campaign default port and the local default display name in the form; saving is still deliberate.

The panel uses normal Control focus, LineEdit and SpinBox behaviour, so keyboard, mouse, controller focus navigation and supported platform virtual keyboards share one input surface. While the form owns text input, lobby polling is suspended. It resumes on the next frame after Save or Back so the same Confirm or Cancel press cannot also activate the parent lobby.

## Command-line launch

Command-line networking arguments remain available for automation, dedicated test scripts and launching several local instances. When any supported networking argument is present, it takes precedence over the saved in-game connection profile.

Host on the campaign default port:

```powershell
Godot_v4.6.2-stable_win64.exe --path C:\GitRepos\epochbound -- --host
```

Host on another UDP port:

```powershell
Godot_v4.6.2-stable_win64.exe --path C:\GitRepos\epochbound -- --host --port=27492 --name=ELI
```

Join as a co-op ally:

```powershell
Godot_v4.6.2-stable_win64.exe --path C:\GitRepos\epochbound -- --join=192.168.1.40 --port=27491 --name=ALLY
```

Request an invasion:

```powershell
Godot_v4.6.2-stable_win64.exe --path C:\GitRepos\epochbound -- --invade --join=192.168.1.40 --port=27491 --name=RED_HOUR
```

For public Internet testing, forward only the selected UDP port to the host machine. Android exports must enable the Internet permission before networking can work.

## Host authority

Clients send only bounded intent:

```text
movement direction
attack requested
monotonic input sequence
```

They do not send:

```text
damage values
health values
inventory changes
quest changes
currency changes
world-state changes
save payloads
boss outcomes
```

The host validates fresh sequence numbers, moves guest actors against the host map and collision model, resolves attacks against host-owned enemies or eligible PvP actors, and broadcasts bounded snapshots.

The server is peer `1`. Remote calls use three logical channels:

| Channel | Transfer | Purpose |
| ---: | --- | --- |
| 0 | Reliable | Join negotiation, rejection, role acceptance and removal |
| 1 | Unreliable ordered | Client movement and attack intent |
| 2 | Unreliable ordered | Host world and peer snapshots |

Late movement or snapshot packets can be discarded rather than stalling newer state. Critical role and lifecycle messages remain reliable.

## Durable progression

**Host saves only.** The host's existing campaign remains authoritative.

Allies can damage enemies and participate in boss arenas, but enemy rewards, pickups, quests, recipes, merchants, equipment, currency and durable outcomes are applied to the host runtime only. Guest profiles do not receive copied host progression.

Invader victories and banishments update only the transient `session_score`. They are not written into a campaign profile.

The save payload validator rejects fields such as:

```text
multiplayer_peers
peer_roles
invasion_state
online_area_id
online_role
```

Manual profiles are blocked while remote peers are present. Host autosaves may continue during peaceful co-op, but defer while an invader is active. Clients never write the host's world state.

The connection profile is also outside durable campaign progression. Its address, port and display name configure a future session but are not captured by `capture_save_profile`, transferred in snapshots or installed with campaign packages.

## Authored online areas

Campaigns opt in through `campaign.json`:

```json
{
  "multiplayer_files": ["multiplayer/core.json"],
  "multiplayer": {
    "enabled": true,
    "transport": "enet",
    "default_port": 27491,
    "max_allies": 2,
    "max_invaders": 1,
    "snapshot_rate_hz": 12,
    "input_rate_hz": 30,
    "shared_progression": "host_only",
    "pvp_rewards": "session_only",
    "friendly_fire": false
  }
}
```

An area record is data-only:

```json
{
  "id": "clockwood_ashen_hunt",
  "display_name": "Clockwood Ashen Hunt",
  "map_id": "clockwood_edge",
  "kind": "pvp",
  "priority": 20,
  "bounds": {"left": 288, "right": 528, "top": 176, "bottom": 320},
  "available_eras": ["ashen"],
  "allow_allies": true,
  "allow_invaders": true,
  "friendly_fire": false,
  "ally_spawn": {"x": 328, "y": 272},
  "invader_spawn": {"x": 488, "y": 272}
}
```

### Area kinds

- **sanctuary** permits allies but never invasion damage.
- **co_op** permits allies and suppresses invaders.
- **pvp** can permit both allies and one invader.

Overlapping areas use the highest `priority`. Equal priorities prefer the smaller area, then stable area ID. This lets a focused PvP arena override a map-wide co-op region without changing the rest of the map.

Every enabled campaign map needs at least one online area. Area bounds and spawn points must remain inside their map. Era bindings must reference real map eras. Only PvP areas may allow invaders.

## Reference campaign

The Hours Beneath currently authors:

| Area | Map | Behaviour |
| --- | --- | --- |
| Bellweather Sanctuary | Bellweather Crossing | Co-op permitted, invasions suppressed |
| Clockwood Fellowship | Clockwood Edge | Map-wide co-op |
| Clockwood Ashen Hunt | Clockwood Edge, Ashen only | Higher-priority invasion area |
| Underworks Fellowship | Museum Underworks | Co-op boss route, invasions suppressed |

The Ashen Hunt overlaps the central Clockwood Hound encounter. A host must stand inside that authored region before an invasion request is accepted.

## Defeat rules

- An ally reduced to zero health becomes inactive and respawns after a bounded session timer.
- An invader reduced to zero health is banished and disconnected after a short presentation delay.
- A host defeat ends active invasions and returns the host through the existing defeat-rewind path.
- Respawned actors receive temporary PvP grace.
- Sanctuary and co-op areas never produce invasion damage.

These are session rules. They do not add new durable currencies, item losses, experience penalties or corpse retrieval.

## Validation

The complete Godot gate directly compiles and executes:

```text
res://tools/compile_multiplayer_probe.gd
res://tools/smoke_multiplayer_session_model.gd
res://tools/smoke_multiplayer_connection_profile.gd
res://tools/smoke_multiplayer_runtime.gd
res://tools/smoke_multiplayer_validation_edges.gd
```

The suite checks:

- hostname, IPv4 and bracketed IPv6 profile handling;
- rejection of URL schemes, paths, whitespace, invalid ports and invalid display names;
- atomic player-local writes, valid-backup rotation and malformed-primary recovery;
- canonical connection-panel composition and Control availability;
- focused text ownership and next-frame lobby polling restoration;
- immediate application of saved address, port and display name to the session;
- separation of connection details from campaign saves and packages;
- party and invasion capacity;
- monotonic client input sequences;
- sanctuary safety;
- PvP hostility only inside one shared authored PvP area;
- co-op friendly-fire suppression;
- co-op enemy damage through the host runtime;
- host and invader damage through host authority;
- temporary downing, respawn and banishment;
- campaign and protocol matching;
- bounded snapshots and stale-snapshot rejection;
- exclusion of durable inventory and story state from snapshots;
- exclusion of online actors from save payloads;
- strict policy types and ranges;
- exact map, era, bounds and spawn validation;
- canonical scene composition;
- read-only release workflow policy;
- exact tracked-source cleanliness after every validation step.

## Security and trust boundary

- Object decoding is not enabled for network traffic.
- Remote peers can call only the declared join and input RPC surfaces.
- Sender identity comes from `multiplayer.get_remote_sender_id()` on the host.
- Clients cannot nominate their peer ID, health, damage, rewards or progression.
- Campaign and release versions must match before role acceptance.
- All campaign packages still pass complete staged validation before installation.
- Saved connection details contain no secret, account token or durable game state.
- The high-level Godot protocol is used only between matching Godot clients; it is not presented as a stable protocol for non-Godot servers.

Host authority reduces casual state tampering but is not a substitute for a production identity service, relay, moderation, telemetry and anti-cheat program.

## Manual test route

1. Launch the host instance, press **N**, open **Connection Setup**, choose the UDP port and display name, save, then select **Host Co-op**.
2. Launch a second instance, press **N**, open **Connection Setup**, enter `127.0.0.1` or the host's LAN address and matching UDP port, save, then select **Join Co-op**.
3. Confirm the ally appears in Bellweather Sanctuary and cannot damage the host.
4. Travel to Clockwood Edge and confirm the ally follows the host map and era.
5. Let the ally strike an Ash Hound and confirm the host owns the enemy health change.
6. Move the host into Clockwood Ashen Hunt.
7. Launch a third instance, enter the same host endpoint through **Connection Setup**, save, then select **Invade**.
8. Confirm host and invader damage works only inside the marked area.
9. Walk outside the invasion area and confirm the invader is removed.
10. Re-enter, invade again and defeat the invader.
11. Confirm the invader is banished and no durable reward appears in the host save.
12. Enter Museum Underworks with the ally and complete the Sentinel route.
13. Have the host choose **Leave Online Session** and confirm both clients report the shutdown request, acknowledge it, receive the commit, return offline and close without being force-killed.
14. Save and reload the host journey and confirm no guest actor or invasion state returns.
15. Restart a client and confirm its saved endpoint and display name reload without changing any campaign save slot.
16. Repeat one launch with `--join`, `--port` or `--name` and confirm command-line values take precedence over the player-local profile.

## Remaining production boundaries

The current implementation is a validated direct-IP vertical slice. Production Internet multiplayer still requires deliberate work on:

- platform invitations, friend discovery or join codes;
- relay and NAT traversal;
- optional dedicated-server orchestration;
- reconnect after host restart and host-migration policy;
- identity, moderation and block lists;
- latency simulation and packet-loss soak testing;
- bandwidth and snapshot profiling on final art/content loads;
- exploit review and authoritative rate limits;
- platform certification and Android/iOS network permissions;
- accessibility and controller usability review with multiple real machines.

### Host-directed disconnect ordering

After every registered client acknowledges the shutdown request, the host broadcasts one reliable commit and keeps the ENet server alive for a bounded flush window. Clients become quiescent but remain connected. The host then disconnects each captured peer, waits for those disconnects to be observed or for the bounded disconnect grace to expire, and only then closes the server. This prevents a client-side close from racing a later high-level send and proves that all peers return offline without harness-forced termination.
