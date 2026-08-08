#!/usr/bin/env python3
"""Patch the temporary applicator's repeated catalogue-return anchor."""

from pathlib import Path

path = Path("tools/temp_apply_boss_music_stems.py")
source = path.read_text(encoding="utf-8")
helper_anchor = '''def append_before(path: str, marker: str, addition: str) -> None:
    replace_once(path, marker, addition + marker)
'''
helper_replacement = '''def replace_count(path: str, old: str, new: str, expected: int) -> None:
    file_path = Path(path)
    source = file_path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != expected:
        raise SystemExit(
            f"{path}: expected {expected} replacement anchors, found {count}: {old[:140]!r}"
        )
    file_path.write_text(source.replace(old, new), encoding="utf-8")


def append_before(path: str, marker: str, addition: str) -> None:
    replace_once(path, marker, addition + marker)
'''
if source.count(helper_anchor) != 1:
    raise SystemExit("temporary applicator helper anchor drifted")
source = source.replace(helper_anchor, helper_replacement, 1)
old_block = '''replace_once(
    "src/content/audio_mood_catalog.gd",
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)',
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)',
)
# The early empty-catalogue return contains the same text after the first replacement.
replace_once(
    "src/content/audio_mood_catalog.gd",
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)',
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)',
)
'''
new_block = '''replace_count(
    "src/content/audio_mood_catalog.gd",
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)',
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)',
    3,
)
'''
if source.count(old_block) != 1:
    raise SystemExit("temporary applicator repeated-return block drifted")
path.write_text(source.replace(old_block, new_block, 1), encoding="utf-8")
print("boss_music_applicator_cardinality_fixed")
