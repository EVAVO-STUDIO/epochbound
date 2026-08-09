#!/usr/bin/env python3
"""Route graceful host teardown through SceneMultiplayer before ENet closes."""

from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return source.replace(old, new, 1)


transport_path = Path("src/multiplayer_transport_session.gd")
transport = transport_path.read_text(encoding="utf-8")
old_disconnect = '''\tif network_peer != null and multiplayer.is_server():
\t\tvar connected_ids: PackedInt32Array = multiplayer.get_peers()
\t\tfor peer_id in host_shutdown_expected_peer_ids:
\t\t\tif connected_ids.has(peer_id):
\t\t\t\tnetwork_peer.disconnect_peer(peer_id)
'''
new_disconnect = '''\tif network_peer != null and multiplayer.is_server():
\t\tvar connected_ids: PackedInt32Array = multiplayer.get_peers()
\t\tfor peer_id in host_shutdown_expected_peer_ids:
\t\t\tif not connected_ids.has(peer_id):
\t\t\t\tcontinue
\t\t\t# SceneMultiplayer removes the peer from its relay set before ENet
\t\t\t# begins closing. Calling ENet directly leaves stale relay state and
\t\t\t# can make Godot send through a peer whose channel count is already 0.
\t\t\tmultiplayer.call("disconnect_peer", peer_id)
\t\t\tif not host_shutdown_disconnected_peer_ids.has(peer_id):
\t\t\t\thost_shutdown_disconnected_peer_ids.append(peer_id)
\t\thost_shutdown_disconnected_peer_ids.sort()
\t\tlast_host_shutdown_disconnect_count = host_shutdown_disconnected_peer_ids.size()
'''
if new_disconnect not in transport:
    transport = replace_once(
        transport,
        old_disconnect,
        new_disconnect,
        "SceneMultiplayer-owned host disconnect",
    )
transport_path.write_text(transport.rstrip() + "\n", encoding="utf-8")

checker_path = Path("tools/check_multiplayer_loopback_contract.py")
checker = checker_path.read_text(encoding="utf-8")
checker = checker.replace(
    "        'network_peer.disconnect_peer(peer_id)',\n",
    "        'multiplayer.call(\"disconnect_peer\", peer_id)',\n",
)
forbidden_anchor = "        'OS.get_unix_time',\n"
forbidden_addition = forbidden_anchor + "        'network_peer.disconnect_peer(peer_id)',\n"
if "        'network_peer.disconnect_peer(peer_id)',\n" not in checker.split("forbid(\n    transport_path", 1)[-1]:
    checker = replace_once(
        checker,
        forbidden_anchor,
        forbidden_addition,
        "low-level ENet disconnect prohibition",
    )
checker_path.write_text(checker.rstrip() + "\n", encoding="utf-8")

doc_path = Path("docs/MULTIPLAYER_LOOPBACK_GATE.md")
doc = doc_path.read_text(encoding="utf-8")
doc_token = "SceneMultiplayer-owned disconnect"
if doc_token not in doc:
    doc = doc.rstrip() + (
        "\n\n- Host teardown uses a SceneMultiplayer-owned disconnect for every "
        "acknowledged peer, clearing relay membership before ENet channel "
        "shutdown and preventing zero-channel sends.\n"
    )
doc_path.write_text(doc.rstrip() + "\n", encoding="utf-8")

print("scene_multiplayer_disconnect_fix_applied")
