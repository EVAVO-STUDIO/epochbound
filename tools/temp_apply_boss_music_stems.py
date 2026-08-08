#!/usr/bin/env python3
"""Apply the data-driven boss phase music stem production slice."""

from __future__ import annotations

import json
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    source = file_path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected one replacement anchor, found {count}: {old[:140]!r}"
        )
    file_path.write_text(source.replace(old, new, 1), encoding="utf-8")


def append_before(path: str, marker: str, addition: str) -> None:
    replace_once(path, marker, addition + marker)


# ---------------------------------------------------------------------------
# Audio catalogue: stable boss|phase definitions shared by runtime and tools.
# ---------------------------------------------------------------------------
replace_once(
    "src/content/audio_mood_catalog.gd",
    '\t\t"profiles": [default_profile()],\n\t\t"bindings": []',
    '\t\t"profiles": [default_profile()],\n\t\t"boss_stems": [],\n\t\t"bindings": []',
)
replace_once(
    "src/content/audio_mood_catalog.gd",
    '''\tvar definitions: Dictionary = {}
\tvar bindings: Array[Dictionary] = []
\tvar sources: Dictionary = {}
\tvar title_profile_id := DEFAULT_PROFILE_ID''',
    '''\tvar definitions: Dictionary = {}
\tvar bindings: Array[Dictionary] = []
\tvar sources: Dictionary = {}
\tvar boss_stems: Dictionary = {}
\tvar boss_stem_sources: Dictionary = {}
\tvar title_profile_id := DEFAULT_PROFILE_ID''',
)
replace_once(
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
replace_once(
    "src/content/audio_mood_catalog.gd",
    '''\t\tvar bindings_value: Variant = data.get("bindings", [])
\t\tif typeof(bindings_value) != TYPE_ARRAY:''',
    '''\t\tvar stems_value: Variant = data.get("boss_stems", [])
\t\tif typeof(stems_value) != TYPE_ARRAY:
\t\t\terrors.append("%s: boss_stems must be an array." % path)
\t\telse:
\t\t\tfor stem_value in stems_value as Array:
\t\t\t\tif typeof(stem_value) != TYPE_DICTIONARY:
\t\t\t\t\terrors.append("%s: every boss stem must be an object." % path)
\t\t\t\t\tcontinue
\t\t\t\tmerge_boss_stem(
\t\t\t\t\tstem_value as Dictionary,
\t\t\t\t\tpath,
\t\t\t\t\tboss_stems,
\t\t\t\t\tboss_stem_sources,
\t\t\t\t\terrors
\t\t\t\t)
\t\tvar bindings_value: Variant = data.get("bindings", [])
\t\tif typeof(bindings_value) != TYPE_ARRAY:''',
)
replace_once(
    "src/content/audio_mood_catalog.gd",
    '\treturn make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id)\n\n\nstatic func merge_profile(',
    '\treturn make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)\n\n\nstatic func merge_profile(',
)
append_before(
    "src/content/audio_mood_catalog.gd",
    "\n\nstatic func make_result(\n",
    '''

static func boss_stem_key(boss_id: String, phase_id: String) -> String:
\treturn "%s|%s" % [boss_id.strip_edges(), phase_id.strip_edges()]


static func merge_boss_stem(
\tstem_data: Dictionary,
\tsource: String,
\tdefinitions: Dictionary,
\tsources: Dictionary,
\terrors: Array[String]
) -> void:
\tvar boss_id := str(stem_data.get("boss_id", "")).strip_edges()
\tvar phase_id := str(stem_data.get("phase_id", "")).strip_edges()
\tvar key := boss_stem_key(boss_id, phase_id)
\tif boss_id.is_empty() or phase_id.is_empty():
\t\terrors.append("%s: boss stem requires boss_id and phase_id." % source)
\t\treturn
\tif definitions.has(key):
\t\terrors.append("%s: boss stem '%s' is also declared by %s." % [source, key, sources.get(key, "another catalogue")])
\t\treturn
\tdefinitions[key] = stem_data.duplicate(true)
\tsources[key] = source


static func boss_stem(definitions: Dictionary, boss_id: String, phase_id: String) -> Dictionary:
\tvar value: Variant = definitions.get(boss_stem_key(boss_id, phase_id), {})
\treturn value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func boss_stem_number(stem_data: Dictionary, key: String, fallback: float) -> float:
\treturn float(stem_data.get(key, fallback))


static func boss_stem_text(stem_data: Dictionary, key: String, fallback: String) -> String:
\treturn str(stem_data.get(key, fallback))


static func boss_stem_integer_array(
\tstem_data: Dictionary,
\tkey: String,
\tfallback: Array[int]
) -> Array[int]:
\tvar output: Array[int] = []
\tvar value: Variant = stem_data.get(key, [])
\tif typeof(value) == TYPE_ARRAY:
\t\tfor entry_value in value as Array:
\t\t\toutput.append(int(entry_value))
\tif output.is_empty():
\t\tfor entry in fallback:
\t\t\toutput.append(entry)
\treturn output
''',
)
replace_once(
    "src/content/audio_mood_catalog.gd",
    '''\tsources: Dictionary,
\ttitle_profile_id: String
) -> Dictionary:''',
    '''\tsources: Dictionary,
\ttitle_profile_id: String,
\tboss_stems: Dictionary,
\tboss_stem_sources: Dictionary
) -> Dictionary:''',
)
replace_once(
    "src/content/audio_mood_catalog.gd",
    '''\t\t"bindings": bindings,
\t\t"sources": sources,
\t\t"title_profile_id": title_profile_id''',
    '''\t\t"bindings": bindings,
\t\t"sources": sources,
\t\t"title_profile_id": title_profile_id,
\t\t"boss_stems": boss_stems,
\t\t"boss_stem_sources": boss_stem_sources''',
)

# ---------------------------------------------------------------------------
# Validation: strict object/phase references, bounded synthesis and coverage.
# ---------------------------------------------------------------------------
replace_once(
    "src/content/audio_mood_validator.gd",
    'const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")',
    'const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")\nconst ObjectCatalog = preload("res://src/content/object_catalog.gd")\nconst BossCatalog = preload("res://src/content/boss_catalog.gd")',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '''\tvar profile_count := 0
\tvar binding_count := 0''',
    '''\tvar profile_count := 0
\tvar binding_count := 0
\tvar boss_stem_count := 0''',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '''\t\tprofile_count += int(report.get("audio_profile_count", 0))
\t\tbinding_count += int(report.get("audio_binding_count", 0))''',
    '''\t\tprofile_count += int(report.get("audio_profile_count", 0))
\t\tbinding_count += int(report.get("audio_binding_count", 0))
\t\tboss_stem_count += int(report.get("boss_stem_count", 0))''',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '''\toutput["audio_profile_count"] = profile_count
\toutput["audio_binding_count"] = binding_count''',
    '''\toutput["audio_profile_count"] = profile_count
\toutput["audio_binding_count"] = binding_count
\toutput["boss_stem_count"] = boss_stem_count''',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '''\toutput["audio_profile_count"] = audio_report.get("audio_profile_count", 0)
\toutput["audio_binding_count"] = audio_report.get("audio_binding_count", 0)''',
    '''\toutput["audio_profile_count"] = audio_report.get("audio_profile_count", 0)
\toutput["audio_binding_count"] = audio_report.get("audio_binding_count", 0)
\toutput["boss_stem_count"] = audio_report.get("boss_stem_count", 0)''',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '''\tvar definitions: Dictionary = catalog_result.get("definitions", {})
\tvar bindings_value: Variant = catalog_result.get("bindings", [])''',
    '''\tvar definitions: Dictionary = catalog_result.get("definitions", {})
\tvar stems_value: Variant = catalog_result.get("boss_stems", {})
\tvar boss_stems: Dictionary = stems_value as Dictionary if typeof(stems_value) == TYPE_DICTIONARY else {}
\tvar stem_sources_value: Variant = catalog_result.get("boss_stem_sources", {})
\tvar boss_stem_sources: Dictionary = stem_sources_value as Dictionary if typeof(stem_sources_value) == TYPE_DICTIONARY else {}
\tvar object_result: Dictionary = ObjectCatalog.load_catalogs(campaign_path, campaign)
\tvar object_definitions_value: Variant = object_result.get("definitions", {})
\tvar object_definitions: Dictionary = object_definitions_value as Dictionary if typeof(object_definitions_value) == TYPE_DICTIONARY else {}
\tif not bool(object_result.get("ok", false)):
\t\terrors.append("%s: boss music stems could not resolve object definitions." % campaign_id)
\tvar stem_keys := PackedStringArray()
\tfor stem_key_value in boss_stems.keys():
\t\tstem_keys.append(str(stem_key_value))
\tstem_keys.sort()
\tfor stem_key in stem_keys:
\t\tvar stem_value: Variant = boss_stems.get(stem_key, {})
\t\tif typeof(stem_value) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvalidate_boss_stem_record(
\t\t\tstem_value as Dictionary,
\t\t\tstr(boss_stem_sources.get(stem_key, campaign_id)),
\t\t\tobject_definitions,
\t\t\terrors,
\t\t\twarnings
\t\t)
\tfor object_id_value in object_definitions.keys():
\t\tvar object_id := str(object_id_value)
\t\tvar definition_value: Variant = object_definitions.get(object_id, {})
\t\tif typeof(definition_value) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvar definition_data: Dictionary = definition_value as Dictionary
\t\tif not BossCatalog.is_boss(definition_data):
\t\t\tcontinue
\t\tfor phase_value in BossCatalog.phases(definition_data):
\t\t\tif typeof(phase_value) != TYPE_DICTIONARY:
\t\t\t\tcontinue
\t\t\tvar phase_id := BossCatalog.phase_id(phase_value as Dictionary)
\t\t\tif phase_id.is_empty():
\t\t\t\tcontinue
\t\t\tvar stem_key := AudioMoodCatalog.boss_stem_key(object_id, phase_id)
\t\t\tif not boss_stems.has(stem_key):
\t\t\t\twarnings.append("%s: enabled boss phase '%s' has no authored boss music stem." % [campaign_id, stem_key])
\tvar bindings_value: Variant = catalog_result.get("bindings", [])''',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '\treturn make_report(errors, warnings, definitions.size(), bindings.size())',
    '\treturn make_report(errors, warnings, definitions.size(), bindings.size(), boss_stems.size())',
)
append_before(
    "src/content/audio_mood_validator.gd",
    "\n\nstatic func validate_integer_sequence(\n",
    '''

static func validate_boss_stem_record(
\tstem_data: Dictionary,
\tsource: String,
\tobject_definitions: Dictionary,
\terrors: Array[String],
\twarnings: Array[String]
) -> void:
\tvar boss_id := str(stem_data.get("boss_id", "")).strip_edges()
\tvar phase_id := str(stem_data.get("phase_id", "")).strip_edges()
\tvar stem_key := AudioMoodCatalog.boss_stem_key(boss_id, phase_id)
\tif not matches(PROFILE_ID_PATTERN, boss_id):
\t\terrors.append("%s: boss stem boss_id '%s' is invalid." % [source, boss_id])
\tif not matches(PROFILE_ID_PATTERN, phase_id):
\t\terrors.append("%s: boss stem phase_id '%s' is invalid." % [source, phase_id])
\tif str(stem_data.get("display_name", "")).strip_edges().is_empty():
\t\terrors.append("%s/%s: display_name is required." % [source, stem_key])
\tvar definition_value: Variant = object_definitions.get(boss_id, {})
\tvar definition_data: Dictionary = definition_value as Dictionary if typeof(definition_value) == TYPE_DICTIONARY else {}
\tif definition_data.is_empty():
\t\terrors.append("%s/%s: boss_id references unknown object '%s'." % [source, stem_key, boss_id])
\telse:
\t\tif not BossCatalog.is_boss(definition_data):
\t\t\terrors.append("%s/%s: boss_id must reference an enabled boss." % [source, stem_key])
\t\tif BossCatalog.phase_by_id(definition_data, phase_id).is_empty():
\t\t\terrors.append("%s/%s: phase_id references unknown boss phase '%s'." % [source, stem_key, phase_id])
\tvalidate_boss_stem_number(stem_data, "tempo_multiplier", 0.5, 2.0, source, stem_key, errors)
\tvalidate_boss_stem_integer(stem_data, "root_offset", -24, 24, source, stem_key, errors)
\tvalidate_boss_stem_sequence(stem_data, "melody_steps", 4, 64, -99, 31, source, stem_key, errors)
\tvalidate_boss_stem_sequence(stem_data, "bass_steps", 4, 64, -99, 31, source, stem_key, errors)
\tvar waveform := str(stem_data.get("waveform", ""))
\tif not WAVEFORMS.has(waveform):
\t\terrors.append("%s/%s: unsupported boss stem waveform '%s'." % [source, stem_key, waveform])
\tvalidate_boss_stem_number(stem_data, "pulse_width", 0.10, 0.90, source, stem_key, errors)
\tvalidate_boss_stem_number(stem_data, "gain", 0.0, 0.25, source, stem_key, errors)
\tvalidate_boss_stem_number(stem_data, "percussion_gain", 0.0, 0.20, source, stem_key, errors)
\tif float(stem_data.get("gain", 0.0)) + float(stem_data.get("percussion_gain", 0.0)) > 0.28:
\t\twarnings.append("%s/%s: combined boss stem gain may mask combat feedback on small speakers." % [source, stem_key])


static func validate_boss_stem_sequence(
\tstem_data: Dictionary,
\tkey: String,
\tminimum_count: int,
\tmaximum_count: int,
\tminimum_value: int,
\tmaximum_value: int,
\tsource: String,
\tstem_key: String,
\terrors: Array[String]
) -> void:
\tvar value: Variant = stem_data.get(key, [])
\tif typeof(value) != TYPE_ARRAY:
\t\terrors.append("%s/%s/%s must be an array." % [source, stem_key, key])
\t\treturn
\tvar entries: Array = value as Array
\tif entries.size() < minimum_count or entries.size() > maximum_count:
\t\terrors.append("%s/%s/%s must contain between %d and %d entries." % [source, stem_key, key, minimum_count, maximum_count])
\tfor entry_value in entries:
\t\tif typeof(entry_value) != TYPE_INT and typeof(entry_value) != TYPE_FLOAT:
\t\t\terrors.append("%s/%s/%s must contain only integers." % [source, stem_key, key])
\t\t\tcontinue
\t\tvar entry := int(entry_value)
\t\tif entry == AudioMoodCatalog.REST_STEP:
\t\t\tcontinue
\t\tif entry < minimum_value or entry > maximum_value:
\t\t\terrors.append("%s/%s/%s entry %d is outside the supported range." % [source, stem_key, key, entry])


static func validate_boss_stem_number(
\tstem_data: Dictionary,
\tkey: String,
\tminimum: float,
\tmaximum: float,
\tsource: String,
\tstem_key: String,
\terrors: Array[String]
) -> void:
\tvar value: Variant = stem_data.get(key, null)
\tif typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
\t\terrors.append("%s/%s/%s must be numeric." % [source, stem_key, key])
\t\treturn
\tvar number_value := float(value)
\tif number_value < minimum or number_value > maximum:
\t\terrors.append("%s/%s/%s must be between %.2f and %.2f." % [source, stem_key, key, minimum, maximum])


static func validate_boss_stem_integer(
\tstem_data: Dictionary,
\tkey: String,
\tminimum: int,
\tmaximum: int,
\tsource: String,
\tstem_key: String,
\terrors: Array[String]
) -> void:
\tvar value: Variant = stem_data.get(key, null)
\tif typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
\t\terrors.append("%s/%s/%s must be numeric." % [source, stem_key, key])
\t\treturn
\tvar integer_value := int(value)
\tif integer_value < minimum or integer_value > maximum:
\t\terrors.append("%s/%s/%s must be between %d and %d." % [source, stem_key, key, minimum, maximum])
''',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    'static func make_report(errors: Array[String], warnings: Array[String], profile_count: int, binding_count: int) -> Dictionary:',
    'static func make_report(errors: Array[String], warnings: Array[String], profile_count: int, binding_count: int, boss_stem_count: int = 0) -> Dictionary:',
)
replace_once(
    "src/content/audio_mood_validator.gd",
    '''\t\t"audio_profile_count": profile_count,
\t\t"audio_binding_count": binding_count''',
    '''\t\t"audio_profile_count": profile_count,
\t\t"audio_binding_count": binding_count,
\t\t"boss_stem_count": boss_stem_count''',
)

# Strict integer preservation for transposition and patterns.
append_before(
    "src/content/audio_mood_strict_validator.gd",
    "\n\nstatic func validate_audio_integrity_only(\n",
    '''

static func validate_boss_stem_record(
\tstem_data: Dictionary,
\tsource: String,
\tobject_definitions: Dictionary,
\terrors: Array[String],
\twarnings: Array[String]
) -> void:
\tBaseValidator.validate_boss_stem_record(stem_data, source, object_definitions, errors, warnings)
\tvalidate_boss_stem_integral_values(stem_data, source, errors)
''',
)
replace_once(
    "src/content/audio_mood_strict_validator.gd",
    '''\tfor profile_id in profile_ids:
\t\tvar profile_value: Variant = definitions.get(profile_id, {})
\t\tif typeof(profile_value) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvalidate_integral_music_values(
\t\t\tprofile_value as Dictionary,
\t\t\tstr(sources.get(profile_id, campaign_path)),
\t\t\terrors
\t\t)
\tvalidate_authored_title_profiles''',
    '''\tfor profile_id in profile_ids:
\t\tvar profile_value: Variant = definitions.get(profile_id, {})
\t\tif typeof(profile_value) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvalidate_integral_music_values(
\t\t\tprofile_value as Dictionary,
\t\t\tstr(sources.get(profile_id, campaign_path)),
\t\t\terrors
\t\t)
\tvar stems_value: Variant = catalog_result.get("boss_stems", {})
\tvar stems: Dictionary = stems_value as Dictionary if typeof(stems_value) == TYPE_DICTIONARY else {}
\tvar stem_sources_value: Variant = catalog_result.get("boss_stem_sources", {})
\tvar stem_sources: Dictionary = stem_sources_value as Dictionary if typeof(stem_sources_value) == TYPE_DICTIONARY else {}
\tvar stem_keys := PackedStringArray()
\tfor stem_key_value in stems.keys():
\t\tstem_keys.append(str(stem_key_value))
\tstem_keys.sort()
\tfor stem_key in stem_keys:
\t\tvar stem_value: Variant = stems.get(stem_key, {})
\t\tif typeof(stem_value) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvalidate_boss_stem_integral_values(
\t\t\tstem_value as Dictionary,
\t\t\tstr(stem_sources.get(stem_key, campaign_path)),
\t\t\terrors
\t\t)
\tvalidate_authored_title_profiles''',
)
append_before(
    "src/content/audio_mood_strict_validator.gd",
    "\n\nstatic func validate_integral_number(\n",
    '''

static func validate_boss_stem_integral_values(
\tstem_data: Dictionary,
\tsource: String,
\terrors: Array[String]
) -> void:
\tvalidate_integral_number(stem_data.get("root_offset", null), "%s/boss_stem/root_offset" % source, errors)
\tfor key in ["melody_steps", "bass_steps"]:
\t\tvar sequence_value: Variant = stem_data.get(key, [])
\t\tif typeof(sequence_value) != TYPE_ARRAY:
\t\t\tcontinue
\t\tfor index in range((sequence_value as Array).size()):
\t\t\tvalidate_integral_number(
\t\t\t\t(sequence_value as Array)[index],
\t\t\t\t"%s/boss_stem/%s[%d]" % [source, key, index],
\t\t\t\terrors
\t\t\t)
''',
)

# ---------------------------------------------------------------------------
# Runtime mixer: stable phase lookup and deterministic stem synthesis.
# ---------------------------------------------------------------------------
replace_once(
    "src/audio_mood_controller.gd",
    '''var definitions: Dictionary = {}
var bindings: Array[Dictionary] = []
var active_profile: Dictionary = {}''',
    '''var definitions: Dictionary = {}
var bindings: Array[Dictionary] = []
var boss_stems: Dictionary = {}
var active_profile: Dictionary = {}''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''var loaded_campaign_key := ""
var loaded_context_key := ""

var music_sample_clock := 0''',
    '''var loaded_campaign_key := ""
var loaded_context_key := ""
var active_boss_stem: Dictionary = {}
var active_boss_stem_key := ""

var music_sample_clock := 0''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''var combat_phase := 0.0
var ambience_phase := 0.0''',
    '''var combat_phase := 0.0
var boss_stem_sample_clock := 0
var boss_stem_phase := 0.0
var boss_stem_bass_phase := 0.0
var boss_stem_mix_current := 0.0
var ambience_phase := 0.0''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''\tdefinitions = result.get("definitions", {})
\tbindings.clear()''',
    '''\tdefinitions = result.get("definitions", {})
\tboss_stems = result.get("boss_stems", {})
\tbindings.clear()''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''\t\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\t\tbindings.clear()''',
    '''\t\tdefinitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
\t\tboss_stems.clear()
\t\tbindings.clear()''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '\tresolve_active_profile(true)\n\n\nfunc _process',
    '\tresolve_active_profile(true)\n\tresolve_active_boss_stem(true)\n\n\nfunc _process',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''\tupdate_events()
\tresolve_active_profile(false)
\tupdate_mix(delta)''',
    '''\tupdate_events()
\tresolve_active_profile(false)
\tresolve_active_boss_stem(false)
\tupdate_mix(delta)''',
)
append_before(
    "src/audio_mood_controller.gd",
    "\n\nfunc update_mix(delta: float) -> void:\n",
    '''

func current_boss_audio_context() -> Dictionary:
\tvar flow := runtime_integer("flow", FLOW_SPLASH)
\tif flow != FLOW_GAME and flow != FLOW_PAUSED:
\t\treturn {}
\tvar engaged := runtime_dictionary("engaged_bosses")
\tvar contexts := runtime_dictionary("boss_contexts")
\tvar phases := runtime_dictionary("boss_phase_ids")
\tvar placement_ids := PackedStringArray()
\tfor placement_id_value in engaged.keys():
\t\tif bool(engaged.get(placement_id_value, false)):
\t\t\tplacement_ids.append(str(placement_id_value))
\tplacement_ids.sort()
\tfor placement_id in placement_ids:
\t\tvar context_value: Variant = contexts.get(placement_id, {})
\t\tif typeof(context_value) != TYPE_DICTIONARY:
\t\t\tcontinue
\t\tvar context: Dictionary = context_value as Dictionary
\t\tvar boss_id := str(context.get("object_id", "")).strip_edges()
\t\tvar phase_id := str(phases.get(placement_id, "")).strip_edges()
\t\tif boss_id.is_empty() or phase_id.is_empty():
\t\t\tcontinue
\t\tvar stem := AudioMoodCatalog.boss_stem(boss_stems, boss_id, phase_id)
\t\tif stem.is_empty():
\t\t\tcontinue
\t\treturn {
\t\t\t"key": AudioMoodCatalog.boss_stem_key(boss_id, phase_id),
\t\t\t"boss_id": boss_id,
\t\t\t"phase_id": phase_id,
\t\t\t"placement_id": placement_id,
\t\t\t"stem": stem
\t\t}
\treturn {}


func resolve_active_boss_stem(force: bool) -> void:
\tvar context := current_boss_audio_context()
\tvar next_key := str(context.get("key", ""))
\tif not force and next_key == active_boss_stem_key:
\t\treturn
\tactive_boss_stem_key = next_key
\tvar stem_value: Variant = context.get("stem", {})
\tactive_boss_stem = (stem_value as Dictionary).duplicate(true) if typeof(stem_value) == TYPE_DICTIONARY else {}
\tboss_stem_sample_clock = 0
\tboss_stem_phase = 0.0
\tboss_stem_bass_phase = 0.0
\tboss_stem_mix_current = 0.0


func boss_stem_snapshot() -> Dictionary:
\treturn {
\t\t"key": active_boss_stem_key,
\t\t"boss_id": str(active_boss_stem.get("boss_id", "")),
\t\t"phase_id": str(active_boss_stem.get("phase_id", "")),
\t\t"sample_clock": boss_stem_sample_clock,
\t\t"tempo_multiplier": AudioMoodCatalog.boss_stem_number(active_boss_stem, "tempo_multiplier", 1.0),
\t\t"melody_step_count": AudioMoodCatalog.boss_stem_integer_array(active_boss_stem, "melody_steps", []).size(),
\t\t"stem": active_boss_stem.duplicate(true)
\t}
''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''\tvar combat_target := 1.0 if combat_is_active() else 0.0
\tcombat_mix_current = lerpf(combat_mix_current, combat_target, clampf(delta * 5.0, 0.0, 1.0))''',
    '''\tvar combat_target := 1.0 if combat_is_active() else 0.0
\tcombat_mix_current = lerpf(combat_mix_current, combat_target, clampf(delta * 5.0, 0.0, 1.0))
\tvar boss_stem_target := 1.0 if not active_boss_stem.is_empty() else 0.0
\tboss_stem_mix_current = lerpf(boss_stem_mix_current, boss_stem_target, clampf(delta * 3.5, 0.0, 1.0))''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''\tvar combat_gain := clampf(AudioMoodCatalog.number(active_profile, "music", "combat_gain", 0.08), 0.0, 0.30)
\tvar samples_per_step := maxi(1, int(SAMPLE_RATE * 60.0 / tempo / 4.0))''',
    '''\tvar combat_gain := clampf(AudioMoodCatalog.number(active_profile, "music", "combat_gain", 0.08), 0.0, 0.30)
\tvar stem_active := not active_boss_stem.is_empty()
\tvar stem_tempo := clampf(tempo * AudioMoodCatalog.boss_stem_number(active_boss_stem, "tempo_multiplier", 1.0), 40.0, 240.0)
\tvar stem_root := clampi(root_midi + int(active_boss_stem.get("root_offset", 0)), 0, 127)
\tvar stem_melody: Array[int] = AudioMoodCatalog.boss_stem_integer_array(active_boss_stem, "melody_steps", [0, REST_STEP, 2, REST_STEP])
\tvar stem_bass: Array[int] = AudioMoodCatalog.boss_stem_integer_array(active_boss_stem, "bass_steps", [0, REST_STEP, REST_STEP, REST_STEP])
\tvar stem_waveform := AudioMoodCatalog.boss_stem_text(active_boss_stem, "waveform", "triangle")
\tvar stem_pulse_width := clampf(AudioMoodCatalog.boss_stem_number(active_boss_stem, "pulse_width", 0.35), 0.10, 0.90)
\tvar stem_gain := clampf(AudioMoodCatalog.boss_stem_number(active_boss_stem, "gain", 0.0), 0.0, 0.25)
\tvar stem_percussion_gain := clampf(AudioMoodCatalog.boss_stem_number(active_boss_stem, "percussion_gain", 0.0), 0.0, 0.20)
\tvar samples_per_step := maxi(1, int(SAMPLE_RATE * 60.0 / tempo / 4.0))
\tvar stem_samples_per_step := maxi(1, int(SAMPLE_RATE * 60.0 / stem_tempo / 4.0))''',
)
replace_once(
    "src/audio_mood_controller.gd",
    '''\t\tif combat_mix_current > 0.001:
\t\t\tvar combat_hz := degree_frequency(root_midi + 24, melody_degree if melody_degree != REST_STEP else 0, scale)
\t\t\tcombat_phase = fmod(combat_phase + combat_hz / SAMPLE_RATE, 1.0)
\t\t\tvar beat_gate := 1.0 if posmod(step_index, 2) == 0 else 0.35
\t\t\tvar percussion := deterministic_noise(music_sample_clock) * pow(1.0 - step_phase, 5.0) * beat_gate
\t\t\tsample += (oscillator("pulse", combat_phase, 0.18) * 0.34 + percussion * 0.20) * combat_mix_current * combat_gain
\t\tsample = soft_clip(sample * music_gain_current)''',
    '''\t\tif combat_mix_current > 0.001:
\t\t\tvar combat_hz := degree_frequency(root_midi + 24, melody_degree if melody_degree != REST_STEP else 0, scale)
\t\t\tcombat_phase = fmod(combat_phase + combat_hz / SAMPLE_RATE, 1.0)
\t\t\tvar beat_gate := 1.0 if posmod(step_index, 2) == 0 else 0.35
\t\t\tvar percussion := deterministic_noise(music_sample_clock) * pow(1.0 - step_phase, 5.0) * beat_gate
\t\t\tsample += (oscillator("pulse", combat_phase, 0.18) * 0.34 + percussion * 0.20) * combat_mix_current * combat_gain
\t\tif stem_active:
\t\t\tvar stem_step_index := int(boss_stem_sample_clock / stem_samples_per_step)
\t\t\tvar stem_step_phase := float(boss_stem_sample_clock % stem_samples_per_step) / float(stem_samples_per_step)
\t\t\tvar stem_envelope := minf(1.0, stem_step_phase / 0.05) * maxf(0.0, 1.0 - stem_step_phase * 0.68)
\t\t\tvar stem_sample := 0.0
\t\t\tvar stem_melody_degree := stem_melody[stem_step_index % stem_melody.size()]
\t\t\tif stem_melody_degree != REST_STEP:
\t\t\t\tvar stem_hz := degree_frequency(stem_root + 12, stem_melody_degree, scale)
\t\t\t\tboss_stem_phase = fmod(boss_stem_phase + stem_hz / SAMPLE_RATE, 1.0)
\t\t\t\tstem_sample += oscillator(stem_waveform, boss_stem_phase, stem_pulse_width) * stem_envelope * stem_gain
\t\t\tvar stem_bass_degree := stem_bass[stem_step_index % stem_bass.size()]
\t\t\tif stem_bass_degree != REST_STEP:
\t\t\t\tvar stem_bass_hz := degree_frequency(stem_root - 12, stem_bass_degree, scale)
\t\t\t\tboss_stem_bass_phase = fmod(boss_stem_bass_phase + stem_bass_hz / SAMPLE_RATE, 1.0)
\t\t\t\tstem_sample += oscillator("triangle", boss_stem_bass_phase, 0.5) * stem_envelope * stem_gain * 0.58
\t\t\tvar stem_beat_gate := 1.0 if posmod(stem_step_index, 2) == 0 else 0.28
\t\t\tvar stem_percussion := deterministic_noise(boss_stem_sample_clock * 37 + 11) * pow(1.0 - stem_step_phase, 6.0) * stem_beat_gate
\t\t\tstem_sample += stem_percussion * stem_percussion_gain
\t\t\tsample += stem_sample * boss_stem_mix_current
\t\t\tboss_stem_sample_clock += 1
\t\tsample = soft_clip(sample * music_gain_current)''',
)
append_before(
    "src/audio_mood_controller.gd",
    "\n\nfunc runtime_vector(property_name: String) -> Vector2:\n",
    '''

func runtime_dictionary(property_name: String) -> Dictionary:
\tvar runtime := runtime_root()
\tif runtime == null:
\t\treturn {}
\tvar value: Variant = runtime.get(property_name)
\treturn value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}
''',
)

# The hardened runtime overrides catalogue loading, so keep the same stem state.
replace_once(
    "src/audio_mood_runtime.gd",
    '''\tdefinitions = result.get("definitions", {})
\tbindings.clear()''',
    '''\tdefinitions = result.get("definitions", {})
\tboss_stems = result.get("boss_stems", {})
\tbindings.clear()''',
)
replace_once(
    "src/audio_mood_runtime.gd",
    '''\t\tdefinitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
\t\tbindings.clear()''',
    '''\t\tdefinitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
\t\tboss_stems.clear()
\t\tbindings.clear()''',
)
replace_once(
    "src/audio_mood_runtime.gd",
    '\tresolve_active_profile(true)\n\n\nfunc current_runtime_campaign_key',
    '\tresolve_active_profile(true)\n\tresolve_active_boss_stem(true)\n\n\nfunc current_runtime_campaign_key',
)

# ---------------------------------------------------------------------------
# Editor and reference content.
# ---------------------------------------------------------------------------
replace_once(
    "addons/epochbound_audio_mood_studio/audio_mood_studio.gd",
    '''var status_label: Label
var binding_label: Label
var tempo: SpinBox''',
    '''var status_label: Label
var binding_label: Label
var boss_stem_label: Label
var tempo: SpinBox''',
)
replace_once(
    "addons/epochbound_audio_mood_studio/audio_mood_studio.gd",
    '''\tbinding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tnavigation.add_child(binding_label)
\tvar validate_button := Button.new()''',
    '''\tbinding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tnavigation.add_child(binding_label)
\tboss_stem_label = Label.new()
\tboss_stem_label.text = "Boss phase stems: 0"
\tboss_stem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tnavigation.add_child(boss_stem_label)
\tvar validate_button := Button.new()''',
)
replace_once(
    "addons/epochbound_audio_mood_studio/audio_mood_studio.gd",
    '''\tvar bindings_value: Variant = current_catalog.get("bindings", [])
\tvar binding_count := (bindings_value as Array).size() if typeof(bindings_value) == TYPE_ARRAY else 0
\tbinding_label.text = "%d map/era binding(s)\\nTitle profile: %s" % [binding_count, str(current_catalog.get("title_profile_id", AudioMoodCatalog.DEFAULT_PROFILE_ID))]''',
    '''\tvar bindings_value: Variant = current_catalog.get("bindings", [])
\tvar binding_count := (bindings_value as Array).size() if typeof(bindings_value) == TYPE_ARRAY else 0
\tbinding_label.text = "%d map/era binding(s)\\nTitle profile: %s" % [binding_count, str(current_catalog.get("title_profile_id", AudioMoodCatalog.DEFAULT_PROFILE_ID))]
\tvar stems_value: Variant = current_catalog.get("boss_stems", [])
\tvar stem_lines := PackedStringArray()
\tif typeof(stems_value) == TYPE_ARRAY:
\t\tfor stem_value in stems_value as Array:
\t\t\tif typeof(stem_value) != TYPE_DICTIONARY:
\t\t\t\tcontinue
\t\t\tvar stem: Dictionary = stem_value as Dictionary
\t\t\tstem_lines.append("%s → %s" % [str(stem.get("boss_id", "boss")), str(stem.get("phase_id", "phase"))])
\tstem_lines.sort()
\tboss_stem_label.text = "Boss phase stems: %d" % stem_lines.size()
\tif not stem_lines.is_empty():
\t\tboss_stem_label.text += "\\n" + "\\n".join(stem_lines)''',
)
append_before(
    "addons/epochbound_audio_mood_studio/audio_mood_studio.gd",
    "\n\nfunc profile_count() -> int:\n",
    '''

func boss_stem_count() -> int:
\tvar value: Variant = current_catalog.get("boss_stems", [])
\treturn (value as Array).size() if typeof(value) == TYPE_ARRAY else 0
''',
)
replace_once(
    "tools/smoke_audio_mood_studio.gd",
    '''\tcheck(studio.profile_count() == 7, "Audio Studio must expose seven reference profiles.")
\tvar pattern: Array[int]''',
    '''\tcheck(studio.profile_count() == 7, "Audio Studio must expose seven reference profiles.")
\tcheck(studio.boss_stem_count() == 3, "Audio Studio must expose the three reference boss stems.")
\tvar pattern: Array[int]''',
)
replace_once(
    "tools/smoke_audio_mood_studio.gd",
    'print("Audio and Mood Studio smoke test passed: strict campaign loading, profile state and pattern editing are coherent.")',
    'print("Audio and Mood Studio smoke test passed: strict campaign loading, profile state, three reference boss stems and pattern editing are coherent.")',
)
replace_once(
    "tools/smoke_audio_mood_validation_edges.gd",
    'const AudioMoodValidator = preload("res://src/content/audio_mood_strict_validator.gd")',
    'const AudioMoodValidator = preload("res://src/content/audio_mood_strict_validator.gd")\nconst ObjectCatalog = preload("res://src/content/object_catalog.gd")\n\nconst REFERENCE_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"',
)
replace_once(
    "tools/smoke_audio_mood_validation_edges.gd",
    '''\tcheck(contains_text(errors, "scale[1] must be an integer"), "Fractional scale entries must be rejected instead of truncated.")
\tvar definitions: Dictionary = {''',
    '''\tcheck(contains_text(errors, "scale[1] must be an integer"), "Fractional scale entries must be rejected instead of truncated.")
\tvar reference_result: Dictionary = Repository.read_json(REFERENCE_CAMPAIGN_PATH)
\tvar reference_campaign: Dictionary = reference_result.get("data", {})
\tvar object_result: Dictionary = ObjectCatalog.load_catalogs(REFERENCE_CAMPAIGN_PATH, reference_campaign)
\tvar object_definitions: Dictionary = object_result.get("definitions", {})
\tvar invalid_stem: Dictionary = {
\t\t"boss_id": "ash_hound",
\t\t"phase_id": "missing_phase",
\t\t"display_name": "",
\t\t"tempo_multiplier": 3.0,
\t\t"root_offset": 1.5,
\t\t"melody_steps": [0, 1.5],
\t\t"bass_steps": [],
\t\t"waveform": "sampled_copy",
\t\t"pulse_width": 1.2,
\t\t"gain": 0.9,
\t\t"percussion_gain": 0.8
\t}
\tvar stem_errors: Array[String] = []
\tvar stem_warnings: Array[String] = []
\tAudioMoodValidator.validate_boss_stem_record(invalid_stem, "edge", object_definitions, stem_errors, stem_warnings)
\tcheck(stem_errors.size() >= 8, "Malformed boss stem must fail strict validation in multiple independent fields.")
\tvar duplicate_stems: Dictionary = {}
\tvar duplicate_sources: Dictionary = {}
\tvar duplicate_errors: Array[String] = []
\tvar valid_stem: Dictionary = {
\t\t"boss_id": "underworks_sentinel",
\t\t"phase_id": "catalogue_measure",
\t\t"display_name": "Catalogue Pulse",
\t\t"tempo_multiplier": 1.0,
\t\t"root_offset": 12,
\t\t"melody_steps": [0, -99, 2, -99],
\t\t"bass_steps": [0, -99, -99, -99],
\t\t"waveform": "triangle",
\t\t"pulse_width": 0.4,
\t\t"gain": 0.1,
\t\t"percussion_gain": 0.03
\t}
\tAudioMoodCatalog.merge_boss_stem(valid_stem, "first", duplicate_stems, duplicate_sources, duplicate_errors)
\tAudioMoodCatalog.merge_boss_stem(valid_stem, "second", duplicate_stems, duplicate_sources, duplicate_errors)
\tcheck(contains_text(duplicate_errors, "also declared"), "Duplicate boss stem keys must be rejected.")
\tvar definitions: Dictionary = {''',
)
replace_once(
    "tools/smoke_audio_mood_validation_edges.gd",
    'print("Audio and Mood validation edge smoke test passed: malformed synthesis, fractional patterns, title profiles and bindings are rejected.")',
    'print("Audio and Mood validation edge smoke test passed: malformed synthesis, fractional patterns, boss stems, title profiles and bindings are rejected.")',
)

# Reference stems are original, bounded procedural phrases layered over the existing themes.
reference_path = Path("campaigns/epochbound_demo/audio/core.json")
reference_audio = json.loads(reference_path.read_text(encoding="utf-8"))
reference_audio["boss_stems"] = [
    {
        "boss_id": "underworks_sentinel",
        "phase_id": "catalogue_measure",
        "display_name": "Catalogue Pulse",
        "tempo_multiplier": 0.92,
        "root_offset": 12,
        "melody_steps": [0, -99, 2, 4, -99, 3, 1, -99],
        "bass_steps": [0, -99, -99, 2, -99, -99, 1, -99],
        "waveform": "triangle",
        "pulse_width": 0.42,
        "gain": 0.10,
        "percussion_gain": 0.035,
    },
    {
        "boss_id": "underworks_sentinel",
        "phase_id": "cinder_measure",
        "display_name": "Cinder Pulse",
        "tempo_multiplier": 1.04,
        "root_offset": 7,
        "melody_steps": [0, 1, -99, 3, 2, -99, 4, 3],
        "bass_steps": [0, -99, 2, -99, 4, -99, 1, -99],
        "waveform": "pulse",
        "pulse_width": 0.20,
        "gain": 0.12,
        "percussion_gain": 0.055,
    },
    {
        "boss_id": "underworks_sentinel",
        "phase_id": "last_accession",
        "display_name": "Last Accession Drive",
        "tempo_multiplier": 1.18,
        "root_offset": 12,
        "melody_steps": [0, 2, 4, 3, 5, 4, 2, -99],
        "bass_steps": [0, -99, 3, -99, 5, -99, 2, -99],
        "waveform": "pulse",
        "pulse_width": 0.16,
        "gain": 0.14,
        "percussion_gain": 0.075,
    },
]
reference_path.write_text(json.dumps(reference_audio, indent="\t") + "\n", encoding="utf-8")

# ---------------------------------------------------------------------------
# Compile, local gate, docs and release contracts.
# ---------------------------------------------------------------------------
replace_once(
    "tools/compile_probe.gd",
    '\t"res://tools/smoke_audio_mood_runtime.gd",\n\t"res://tools/smoke_audio_mood_studio.gd",',
    '\t"res://tools/smoke_audio_mood_runtime.gd",\n\t"res://tools/smoke_boss_music_stems.gd",\n\t"res://tools/smoke_audio_mood_studio.gd",',
)
replace_once(
    "scripts/validate.ps1",
    '@("Smoke test original procedural music ambience and event feedback", "res://tools/smoke_audio_mood_runtime.gd"),',
    '@("Smoke test original procedural music ambience and event feedback", "res://tools/smoke_audio_mood_runtime.gd"),\n        @("Smoke test authored boss phase music stems", "res://tools/smoke_boss_music_stems.gd"),',
)
replace_once(
    "scripts/validate.ps1",
    'meaningful temporal shifts, locked combat telegraphs, stagger interrupts, multi-source affordability, regional supply, scarcity, sprite-animation, environment and combat-readability validation',
    'meaningful temporal shifts, locked combat telegraphs, stagger interrupts, boss phase music stems, multi-source affordability, regional supply, scarcity, sprite-animation, environment and combat-readability validation',
)
replace_once(
    "docs/AUDIO_MOOD_STUDIO.md",
    '''The exploration theme continues underneath, avoiding a jarring complete track restart for every small encounter. Boss direction can later extend this same contract with authored phase-specific stems rather than replacing it.

## Ambience profile''',
    '''The exploration theme continues underneath, avoiding a jarring complete track restart for every small encounter.

## Boss phase stems

Boss phases may now add an authored deterministic stem through the Audio catalogue's `boss_stems` array. Each record binds one stable boss definition ID to one stable phase ID and layers its own tempo multiplier, transposition, melody, bass, waveform and percussion pressure over the active map-and-era theme.

The runtime never hard-codes the reference Sentinel. It resolves the currently engaged boss and phase, resets only the phase-stem clock when that key changes, and fades the stem away when the encounter ends. The ordinary exploration profile, ambience, ducking and player volume settings continue underneath.

Audio & Mood Studio displays loaded boss/phase bindings beside the normal profile summary. See [`BOSS_MUSIC_STEMS.md`](BOSS_MUSIC_STEMS.md) for the complete schema, validation and listening contract.

## Ambience profile''',
)
replace_once(
    "docs/AUDIO_MOOD_STUDIO.md",
    '''- missing or oversized scale and sequence data;
- sequence values outside the supported degree range;
- ducking or transition values outside production bounds.''',
    '''- missing or oversized scale and sequence data;
- sequence values outside the supported degree range;
- unknown, duplicate or malformed boss phase stems;
- boss stems that reference a non-boss object or unknown phase;
- ducking or transition values outside production bounds.''',
)
replace_once(
    "README.md",
    '''22. Versioned player-local Audio, presentation and accessibility settings with persistent keyboard and controller remapping

The runtime still uses generated visuals''',
    '''22. Versioned player-local Audio, presentation and accessibility settings with persistent keyboard and controller remapping
23. Authored boss phase music stems that layer Catalogue Measure, Cinder Measure and Last Accession over the current Underworks era theme

The runtime still uses generated visuals''',
)
replace_once(
    "README.md",
    '''- a combat layer that fades over the continuing exploration theme;
- feedback for attacks, impacts, damage, pickups, travel, shifts, menus, dialogue, combat and cinematics;''',
    '''- a combat layer that fades over the continuing exploration theme;
- stable boss-and-phase stems that escalate authored encounters without replacing map-and-era identity;
- feedback for attacks, impacts, damage, pickups, travel, shifts, menus, dialogue, combat and cinematics;''',
)
replace_once(
    "README.md",
    '- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)\n- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)',
    '- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)\n- [`docs/BOSS_MUSIC_STEMS.md`](docs/BOSS_MUSIC_STEMS.md)\n- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)',
)
replace_once(
    "README.md",
    '''- projectile camera conversion, shared combat depth, ammo HUD, boss status, duplicate suppression and pause-layer regressions.

Any logged''',
    '''- projectile camera conversion, shared combat depth, ammo HUD, boss status, duplicate suppression and pause-layer regressions;
- boss phase stem references, deterministic phase selection, era continuity, clock resets and final-phase escalation.

Any logged''',
)
replace_once(
    "README.md",
    '''The workflows verify the official Godot 4.6.2 archive against published SHA-512 sums, check out the exact commit, run their governed gates and confirm validation leaves tracked source unchanged. The primary receipt records zero reference content warnings, zero reference audit warnings, passed meaningful temporal-shift validation and a passed warning-free release-readiness gate.''',
    '''The workflows verify the official Godot 4.6.2 archive against published SHA-512 sums, check out the exact commit, run their governed gates and confirm validation leaves tracked source unchanged. The primary receipt records zero reference content warnings, zero reference audit warnings, passed meaningful temporal-shift validation, `bossMusicStemValidation`, and a passed warning-free release-readiness gate.''',
)
replace_once(
    "README.md",
    '''The next coherent layers build on these contracts rather than replacing them: final original sprite atlases and animation masters, recorded ambience, sound effects and music masters, localisation, boss phase-specific music stems, automated long-form progression playthroughs and deeper economy-balance simulation.''',
    '''The next coherent layers build on these contracts rather than replacing them: final original sprite atlases and animation masters, recorded ambience, sound effects and music masters, localisation, automated long-form progression playthroughs, deeper economy-balance simulation and broader multi-boss music authoring previews.''',
)

# Main and focused workflows are validated in the temporary checkout, then
# published separately through the connector because Actions tokens cannot
# modify workflow files.
replace_once(
    ".github/workflows/validate.yml",
    '''      - name: Validate combat telegraph fairness contract
        run: python3 tools/check_combat_fairness_contract.py

      - name: Validate canonical runtime composition contract''',
    '''      - name: Validate combat telegraph fairness contract
        run: python3 tools/check_combat_fairness_contract.py

      - name: Validate boss phase music stem contract
        run: python3 tools/check_boss_music_stem_contract.py

      - name: Validate canonical runtime composition contract''',
)
replace_once(
    ".github/workflows/validate.yml",
    '# Receipt schema migrated from: "schemaVersion": "2.2"\n          payload = {\n              "schemaVersion": "2.3",',
    '# Receipt schema migrated from: "schemaVersion": "2.3"\n          payload = {\n              "schemaVersion": "2.4",',
)
replace_once(
    ".github/workflows/validate.yml",
    '              "combatFairnessValidation": "passed",\n              "presentationValidation": "passed",',
    '              "combatFairnessValidation": "passed",\n              "bossMusicStemValidation": "passed",\n              "presentationValidation": "passed",',
)
replace_once(
    ".github/workflows/audio-mood-validation.yml",
    '''      - name: Validate release workflow policy
        run: python3 tools/check_release_workflow_policy.py

      - name: Validate canonical runtime composition contract''',
    '''      - name: Validate release workflow policy
        run: python3 tools/check_release_workflow_policy.py

      - name: Validate boss phase music stem contract
        run: python3 tools/check_boss_music_stem_contract.py

      - name: Validate canonical runtime composition contract''',
)
replace_once(
    ".github/workflows/audio-mood-validation.yml",
    '          run_test res://tools/smoke_audio_mood_runtime.gd\n          run_test res://tools/smoke_audio_mood_studio.gd',
    '          run_test res://tools/smoke_audio_mood_runtime.gd\n          run_test res://tools/smoke_boss_music_stems.gd\n          run_test res://tools/smoke_audio_mood_studio.gd',
)

# Receipt consumers advance together. Do not rewrite this new checker's own
# expected migration token.
for checker_path in sorted(Path("tools").glob("check_*_contract.py")):
    if checker_path.name == "check_boss_music_stem_contract.py":
        continue
    source = checker_path.read_text(encoding="utf-8")
    updated = source.replace(
        '# Receipt schema migrated from: "schemaVersion": "2.2"',
        '# Receipt schema migrated from: "schemaVersion": "2.3"',
    )
    updated = updated.replace('"schemaVersion": "2.3"', '"schemaVersion": "2.4"')
    if updated != source:
        checker_path.write_text(updated, encoding="utf-8")

replace_once(
    "tools/check_release_workflow_policy.py",
    '        "python3 tools/check_combat_fairness_contract.py",\n        "python3 tools/check_runtime_scene_contract.py",',
    '        "python3 tools/check_combat_fairness_contract.py",\n        "python3 tools/check_boss_music_stem_contract.py",\n        "python3 tools/check_runtime_scene_contract.py",',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '        \'"combatFairnessValidation": "passed"\',\n        \'"supplyRegionValidation": "passed"\',',
    '        \'"combatFairnessValidation": "passed"\',\n        \'"bossMusicStemValidation": "passed"\',\n        \'"supplyRegionValidation": "passed"\',',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '''        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",''',
    '''        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_boss_music_stem_contract.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",''',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '        "smoke_audio_mood_runtime.gd",\n        "smoke_audio_mood_studio.gd",',
    '        "smoke_audio_mood_runtime.gd",\n        "smoke_boss_music_stems.gd",\n        "smoke_audio_mood_studio.gd",',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '        "smoke_temporal_shift_audit.gd",\n        "meaningful temporal shifts",',
    '        "smoke_temporal_shift_audit.gd",\n        "meaningful temporal shifts",\n        "smoke_boss_music_stems.gd",\n        "boss phase music stems",',
)
append_before(
    "tools/check_release_workflow_policy.py",
    '\n\nmultiplayer_session = read("multiplayer_session", ROOT / "src/multiplayer_session.gd")',
    '''

boss_music_stem_contract = read(
    "boss_music_stem_contract",
    ROOT / "tools/check_boss_music_stem_contract.py",
)
require(
    "boss_music_stem_contract",
    boss_music_stem_contract,
    [
        "epochbound_boss_music_stem_contract_passed",
        "underworks_sentinel|catalogue_measure",
        "underworks_sentinel|cinder_measure",
        "underworks_sentinel|last_accession",
        '"bossMusicStemValidation": "passed"',
    ],
)
''',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    'print("- runtime composition, player settings, persistent controls, warning-safe editor icons, leak-free headless cleanup, meaningful temporal shifts, locked combat telegraphs, stagger interrupts, warning-free reference readiness, progression affordability and regional supply entrypoints are guarded before Godot execution")',
    'print("- runtime composition, player settings, persistent controls, warning-safe editor icons, leak-free headless cleanup, meaningful temporal shifts, locked combat telegraphs, stagger interrupts, boss phase music stems, warning-free reference readiness, progression affordability and regional supply entrypoints are guarded before Godot execution")',
)

print("boss_music_stem_integration_applied")
