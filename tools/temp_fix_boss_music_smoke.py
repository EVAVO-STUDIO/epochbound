#!/usr/bin/env python3
"""Make the boss-music regression resolve the normal era profile before asserting it."""

from pathlib import Path

path = Path("tools/smoke_boss_music_stems.gd")
source = path.read_text(encoding="utf-8")
old = '''\truntime.call("shift_to_next_era")
\tcontroller.call("resolve_active_boss_stem", false)
'''
new = '''\truntime.call("shift_to_next_era")
\tcontroller.call("resolve_active_profile", false)
\tcontroller.call("resolve_active_boss_stem", false)
'''
if source.count(old) != 1:
    raise SystemExit("boss music era-profile regression anchor drifted")
path.write_text(source.replace(old, new, 1), encoding="utf-8")
print("boss_music_smoke_profile_resolution_fixed")
