#!/usr/bin/env python3
"""Patch temporary applicator cardinality and source anchors."""

from pathlib import Path

path = Path("tools/temp_apply_boss_music_stems.py")
source = path.read_text(encoding="utf-8")


def patch_once(label: str, old: str, new: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"temporary applicator {label} drifted: expected 1, found {count}")
    source = source.replace(old, new, 1)


patch_once(
    "helper",
    '''def append_before(path: str, marker: str, addition: str) -> None:
    replace_once(path, marker, addition + marker)
''',
    '''def replace_count(path: str, old: str, new: str, expected: int) -> None:
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
''',
)
patch_once(
    "repeated catalogue returns",
    '''replace_once(
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
''',
    '''replace_count(
    "src/content/audio_mood_catalog.gd",
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)',
    'return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)',
    3,
)
''',
)
patch_once(
    "redundant final catalogue return",
    r'''replace_once(
    "src/content/audio_mood_catalog.gd",
    '\treturn make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)\n\n\nstatic func merge_profile(',
    '\treturn make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)\n\n\nstatic func merge_profile(',
)
''',
    "",
)
patch_once(
    "strict validator signature",
    r'''    "\n\nstatic func validate_audio_integrity_only(\n",
''',
    r'''    "\n\nstatic func validate_audio_integrity_only(campaign_path: String) -> Dictionary:\n",
''',
)
patch_once(
    "strict integral signature",
    r'''    "\n\nstatic func validate_integral_number(\n",
''',
    r'''    "\n\nstatic func validate_integral_number(value: Variant, label: String, errors: Array[String]) -> void:\n",
''',
)
patch_once(
    "nested controller fallback",
    r'''\t\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\t\tbindings.clear()''',
    r'''\t\t\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\t\t\tbindings.clear()''',
)
patch_once(
    "nested controller replacement",
    r'''\t\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\t\tboss_stems.clear()
\t\tbindings.clear()''',
    r'''\t\t\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\t\t\tboss_stems.clear()
\t\t\tbindings.clear()''',
)

path.write_text(source, encoding="utf-8")
print("boss_music_applicator_cardinality_fixed")
