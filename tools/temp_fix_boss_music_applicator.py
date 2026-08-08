#!/usr/bin/env python3
"""Patch temporary applicator cardinality and source anchors."""

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
source = source.replace(old_block, new_block, 1)
redundant_block = '''replace_once(
    "src/content/audio_mood_catalog.gd",
    '\\treturn make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)\\n\\n\\nstatic func merge_profile(',
    '\\treturn make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)\\n\\n\\nstatic func merge_profile(',
)
'''
if source.count(redundant_block) != 1:
    raise SystemExit("temporary applicator redundant final-return block drifted")
source = source.replace(redundant_block, "", 1)
for old_marker, new_marker, label in (
    (
        '    "\\n\\nstatic func validate_audio_integrity_only(\\n",\n',
        '    "\\n\\nstatic func validate_audio_integrity_only(campaign_path: String) -> Dictionary:\\n",\n',
        "strict-validator",
    ),
    (
        '    "\\n\\nstatic func validate_integral_number(\\n",\n',
        '    "\\n\\nstatic func validate_integral_number(value: Variant, label: String, errors: Array[String]) -> void:\\n",\n',
        "strict-integral",
    ),
):
    if source.count(old_marker) != 1:
        raise SystemExit(f"temporary applicator {label} marker drifted")
    source = source.replace(old_marker, new_marker, 1)
controller_old = '''    '''\\t\\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\\t\\tbindings.clear()''',
    '''\\t\\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\\t\\tboss_stems.clear()
\\t\\tbindings.clear()''',
'''
controller_new = '''    '''\\t\\t\\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\\t\\t\\tbindings.clear()''',
    '''\\t\\t\\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\\t\\t\\tboss_stems.clear()
\\t\\t\\tbindings.clear()''',
'''
if source.count(controller_old) != 1:
    raise SystemExit("temporary applicator nested Audio fallback anchor drifted")
source = source.replace(controller_old, controller_new, 1)
path.write_text(source, encoding="utf-8")
print("boss_music_applicator_cardinality_fixed")
