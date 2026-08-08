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
patch_once(
    "nested hardened runtime fallback",
    r'''\t\tdefinitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
\t\tbindings.clear()''',
    r'''\t\t\tdefinitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
\t\t\tbindings.clear()''',
)
patch_once(
    "nested hardened runtime replacement",
    r'''\t\tdefinitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
\t\tboss_stems.clear()
\t\tbindings.clear()''',
    r'''\t\t\tdefinitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
\t\t\tboss_stems.clear()
\t\t\tbindings.clear()''',
)
patch_once(
    "repeated README Audio links",
    r'''replace_once(
    "README.md",
    '- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)\n- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)',
    '- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)\n- [`docs/BOSS_MUSIC_STEMS.md`](docs/BOSS_MUSIC_STEMS.md)\n- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)',
)
''',
    r'''replace_count(
    "README.md",
    '- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)\n- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)',
    '- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)\n- [`docs/BOSS_MUSIC_STEMS.md`](docs/BOSS_MUSIC_STEMS.md)\n- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)',
    2,
)
''',
)
patch_once(
    "focused Audio release policy anchor",
    """replace_once(
    "tools/check_release_workflow_policy.py",
    '''        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",''',
    '''        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_boss_music_stem_contract.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",''',
)
""",
    """replace_once(
    "tools/check_release_workflow_policy.py",
    '''require(
    "audio_mood",
    sources["audio_mood"],
    [
        "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955",
        "persist-credentials: false",
        "ref: ${{ inputs.expected_sha }}",
        "SHA512-SUMS.txt",
        "sha512sum --check",
        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",''',
    '''require(
    "audio_mood",
    sources["audio_mood"],
    [
        "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955",
        "persist-credentials: false",
        "ref: ${{ inputs.expected_sha }}",
        "SHA512-SUMS.txt",
        "sha512sum --check",
        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_boss_music_stem_contract.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",''',
)
""",
)
patch_once(
    "final contract precision",
    'print("boss_music_stem_integration_applied")\n',
    '''contract_path = Path("tools/check_boss_music_stem_contract.py")
contract_source = contract_path.read_text(encoding="utf-8")
forbidden_line = '        "load(",\\n'
if contract_source.count(forbidden_line) != 1:
    raise SystemExit("boss music contract broad load token drifted")
contract_path.write_text(contract_source.replace(forbidden_line, "", 1), encoding="utf-8")

policy_path = Path("tools/check_release_workflow_policy.py")
policy_source = policy_path.read_text(encoding="utf-8")
old_schema = '\"schemaVersion\": \"2.3\"'
new_schema = '\"schemaVersion\": \"2.4\"'
if policy_source.count(old_schema) != 1:
    raise SystemExit("release policy receipt schema token drifted")
policy_path.write_text(policy_source.replace(old_schema, new_schema, 1), encoding="utf-8")

prior_marker = '# Receipt schema migrated from: "schemaVersion": "2.4"'
restored_marker = '# Receipt schema migrated from: "schemaVersion": "2.3"'
for checker_path in sorted(Path("tools").glob("check_*_contract.py")):
    checker_source = checker_path.read_text(encoding="utf-8")
    if prior_marker not in checker_source:
        continue
    checker_path.write_text(checker_source.replace(prior_marker, restored_marker), encoding="utf-8")

print("boss_music_stem_integration_applied")
''',
)

path.write_text(source, encoding="utf-8")

checker_path = Path("tools/check_boss_music_stem_contract.py")
checker_source = checker_path.read_text(encoding="utf-8")
checker_old = '''        expected = {
            ("underworks_sentinel", "catalogue_measure"),
            ("underworks_sentinel", "cinder_measure"),
            ("underworks_sentinel", "last_accession"),
        }
        actual = {
            (str(stem.get("boss_id", "")), str(stem.get("phase_id", "")))
            for stem in stems
            if isinstance(stem, dict)
        }
'''
checker_new = '''        expected = {
            "underworks_sentinel|catalogue_measure",
            "underworks_sentinel|cinder_measure",
            "underworks_sentinel|last_accession",
        }
        actual = {
            f"{str(stem.get('boss_id', ''))}|{str(stem.get('phase_id', ''))}"
            for stem in stems
            if isinstance(stem, dict)
        }
'''
if checker_source.count(checker_old) != 1:
    raise SystemExit("boss music contract reference-key block drifted")
checker_path.write_text(checker_source.replace(checker_old, checker_new, 1), encoding="utf-8")

print("boss_music_applicator_cardinality_fixed")
