import json
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one occurrence, found {text.count(old)}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


campaign_path = Path("campaigns/epochbound_demo/campaign.json")
campaign = json.loads(campaign_path.read_text(encoding="utf-8"))
campaign["cinematic_files"] = ["cinematics/core.json"]
campaign["intro_cinematic_id"] = "storm_door_opening"
campaign["boss_cinematics"] = {
    "underworks_sentinel": {
        "intro_cinematic_id": "underworks_sentinel_intro",
        "defeat_cinematic_id": "underworks_sentinel_defeat",
    }
}
campaign_path.write_text(json.dumps(campaign, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")

repository = Path("src/content/campaign_repository.gd")
text = repository.read_text(encoding="utf-8")
if 'const CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")' not in text:
    text = text.replace(
        'const EconomyCatalog = preload("res://src/content/economy_catalog.gd")\n',
        'const EconomyCatalog = preload("res://src/content/economy_catalog.gd")\nconst CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")\n',
        1,
    )
if 'cinematic_catalog_path :=' not in text:
    marker = '''\tvar economy_catalog_result := save_json(economy_catalog_path, EconomyCatalog.default_catalog())
\tif not economy_catalog_result.get("ok", false):
\t\treturn economy_catalog_result
'''
    addition = marker + '''\tvar cinematic_catalog_path := campaign_directory.path_join("cinematics").path_join("core.json")
\tvar cinematic_catalog_result := save_json(cinematic_catalog_path, CinematicCatalog.default_catalog())
\tif not cinematic_catalog_result.get("ok", false):
\t\treturn cinematic_catalog_result
'''
    if marker not in text:
        raise SystemExit("Campaign repository economy creation marker missing")
    text = text.replace(marker, addition, 1)
if '"cinematic_catalog_path": cinematic_catalog_path' not in text:
    text = text.replace(
        '\t\t"economy_catalog_path": economy_catalog_path,\n',
        '\t\t"economy_catalog_path": economy_catalog_path,\n\t\t"cinematic_catalog_path": cinematic_catalog_path,\n',
        1,
    )
if '"cinematic_files": ["cinematics/core.json"]' not in text:
    text = text.replace(
        '\t\t"economy_files": ["economy/core.json"],\n',
        '\t\t"economy_files": ["economy/core.json"],\n\t\t"cinematic_files": ["cinematics/core.json"],\n\t\t"intro_cinematic_id": "arrival",\n',
        1,
    )
repository.write_text(text, encoding="utf-8", newline="\n")

runtime = Path("src/cinematic_runtime.gd")
text = runtime.read_text(encoding="utf-8")
text = text.replace(
    'var cinematic_id := str(boss_record.get("intro_cinematic_id", "")).strip_edges()',
    'var cinematic_id := boss_cinematic_id(object_id, "intro_cinematic_id", boss_record)',
)
text = text.replace(
    'var cinematic_id := str(boss_record.get("defeat_cinematic_id", "")).strip_edges()',
    'var cinematic_id := boss_cinematic_id(str(context.get("object_id", "")), "defeat_cinematic_id", boss_record)',
)
if "func boss_cinematic_id(" not in text:
    anchor = '\n\nfunc interact() -> void:\n'
    helper = '''

func boss_cinematic_id(object_id: String, field: String, boss_record: Dictionary) -> String:
\tvar authored := str(boss_record.get(field, "")).strip_edges()
\tif not authored.is_empty():
\t\treturn authored
\tvar mapping_value: Variant = campaign.get("boss_cinematics", {})
\tif typeof(mapping_value) != TYPE_DICTIONARY:
\t\treturn ""
\tvar record_value: Variant = (mapping_value as Dictionary).get(object_id, {})
\tif typeof(record_value) != TYPE_DICTIONARY:
\t\treturn ""
\treturn str((record_value as Dictionary).get(field, "")).strip_edges()
'''
    if anchor not in text:
        raise SystemExit("Cinematic runtime interaction insertion point missing")
    text = text.replace(anchor, helper + anchor, 1)
runtime.write_text(text, encoding="utf-8", newline="\n")

project = Path("project.godot")
text = project.read_text(encoding="utf-8")
plugin = '"res://addons/epochbound_cinematic_studio/plugin.cfg"'
if plugin not in text:
    text = text.replace(
        '"res://addons/epochbound_boss_studio/plugin.cfg")',
        '"res://addons/epochbound_boss_studio/plugin.cfg", "res://addons/epochbound_cinematic_studio/plugin.cfg")',
        1,
    )
project.write_text(text, encoding="utf-8", newline="\n")

scene = Path("src/app.tscn")
text = scene.read_text(encoding="utf-8").replace("res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd")
scene.write_text(text, encoding="utf-8", newline="\n")

compile_probe = Path("tools/compile_probe.gd")
text = compile_probe.read_text(encoding="utf-8")
additions = [
    ('\t"res://src/boss_runtime.gd",\n', '\t"res://src/boss_runtime.gd",\n\t"res://src/cinematic_runtime.gd",\n'),
    ('\t"res://src/content/boss_validator.gd",\n', '\t"res://src/content/boss_validator.gd",\n\t"res://src/content/cinematic_catalog.gd",\n\t"res://src/content/cinematic_validator.gd",\n'),
    ('\t"res://addons/epochbound_boss_studio/plugin.gd",\n', '\t"res://addons/epochbound_boss_studio/plugin.gd",\n\t"res://addons/epochbound_cinematic_studio/cinematic_studio.gd",\n\t"res://addons/epochbound_cinematic_studio/plugin.gd",\n'),
    ('\t"res://tools/smoke_boss_validation_edges.gd",\n', '\t"res://tools/smoke_boss_validation_edges.gd",\n\t"res://tools/smoke_cinematic_runtime.gd",\n\t"res://tools/smoke_cinematic_studio.gd",\n\t"res://tools/smoke_cinematic_validation_edges.gd",\n'),
]
for old, new in additions:
    if new not in text:
        if old not in text:
            raise SystemExit(f"Compile probe marker missing: {old!r}")
        text = text.replace(old, new, 1)
text = text.replace("all eleven editors", "all twelve editors")
compile_probe.write_text(text, encoding="utf-8", newline="\n")

validate = Path("tools/validate_content.gd")
text = validate.read_text(encoding="utf-8")
text = text.replace(
    'const EquipmentValidator = preload("res://src/content/boss_validator.gd")',
    'const EquipmentValidator = preload("res://src/content/cinematic_validator.gd")',
    1,
)
if "%d cinematic(s)" not in text:
    text = text.replace(
        ', %d boss reinforcement(s), %d warning(s), %d error(s)." % [',
        ', %d boss reinforcement(s), %d cinematic(s), %d cinematic step(s), %d cinematic trigger(s), %d warning(s), %d error(s)." % [',
        1,
    )
    text = text.replace(
        '\t\t\treport.get("boss_reinforcement_count", 0),\n\t\t\treport.get("warnings", []).size(),',
        '\t\t\treport.get("boss_reinforcement_count", 0),\n\t\t\treport.get("cinematic_count", 0),\n\t\t\treport.get("cinematic_step_count", 0),\n\t\t\treport.get("cinematic_trigger_count", 0),\n\t\t\treport.get("warnings", []).size(),',
        1,
    )
validate.write_text(text, encoding="utf-8", newline="\n")

workflow = Path(".github/workflows/validate.yml")
text = workflow.read_text(encoding="utf-8")
cinematic_lines = (
    '          run_godot_test res://tools/smoke_cinematic_runtime.gd "Cinematic playback skip and durable completion"\n'
    '          run_godot_test res://tools/smoke_cinematic_studio.gd "Cinematic and Timeline Studio editor state"\n'
    '          run_godot_test res://tools/smoke_cinematic_validation_edges.gd "Malformed cinematic maps steps targets effects and checkpoints"\n'
)
if cinematic_lines not in text:
    marker = '          run_godot_test res://tools/smoke_boss_validation_edges.gd "Malformed boss arenas phases patterns rewards and reinforcements"\n'
    if marker not in text:
        raise SystemExit("Boss workflow marker missing")
    text = text.replace(marker, marker + cinematic_lines, 1)
workflow.write_text(text, encoding="utf-8", newline="\n")

powershell = Path("scripts/validate.ps1")
text = powershell.read_text(encoding="utf-8")
if "res://tools/smoke_cinematic_runtime.gd" not in text:
    marker = '    Write-Host "`nEpochbound project and all eleven authoring systems passed complete boss-aware validation."\n'
    block = '''    Invoke-GodotStep "Smoke test cinematic playback skip and durable completion" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_cinematic_runtime.gd"
    )

    Invoke-GodotStep "Smoke test Cinematic and Timeline Studio editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_cinematic_studio.gd"
    )

    Invoke-GodotStep "Smoke test malformed cinematic maps steps targets effects and checkpoints" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_cinematic_validation_edges.gd"
    )

    Write-Host "`nEpochbound project and all twelve authoring systems passed complete cinematic-aware validation."
'''
    if marker not in text:
        raise SystemExit("Boss PowerShell completion marker missing")
    text = text.replace(marker, block, 1)
powershell.write_text(text, encoding="utf-8", newline="\n")

for path in sorted(Path("tools").glob("smoke_*.gd")):
    if path.name.startswith("smoke_cinematic_"):
        continue
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        '== "res://src/boss_runtime.gd"',
        'in ["res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd"]',
    )
    if '"res://src/boss_runtime.gd"' in text and '"res://src/cinematic_runtime.gd"' not in text:
        text = text.replace(
            '"res://src/boss_runtime.gd"',
            '"res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd"',
        )
    path.write_text(text, encoding="utf-8", newline="\n")

readme = Path("README.md")
text = readme.read_text(encoding="utf-8")
if "## Cinematic & Timeline Studio" not in text:
    text = text.replace(
        "36. Cross-era phase changes, locked exits and durable boss outcomes\n37. Pause, resume and safe transition flow",
        "36. Cross-era phase changes, locked exits and durable boss outcomes\n37. Skippable cinematic timelines with camera, actor blocking, fades and dialogue\n38. Save-safe skip equivalence, campaign openings and boss introductions and conclusions\n39. Pause, resume and safe transition flow",
        1,
    )
    section = '''## Cinematic & Timeline Studio

The **Cinematic** main-screen editor authors skippable, save-safe presentation timelines using the same maps, placements, Story effects and durable state as the rest of the campaign. It can:

- author camera targets, pans and constrained zoom;
- block Eli, Morrow and placed actors along timed paths;
- present era-aware dialogue with confirm or timed advancement;
- author fades, waits, era transitions, checkpoints and typed effects;
- trigger sequences from campaign openings, interactions and boss profiles;
- guarantee that skipping applies the same durable completion outcome;
- block save operations while transient timeline state is unresolved;
- preview ordered steps and roll back invalid source edits.

The reference campaign includes **The Door Beneath Bellweather**, **The Sentinel Seals the Gallery** and **The Missing Accession**. Watched and skipped paths publish stable completion keys, reevaluate story progression and request autosave only after normal gameplay control returns.

'''
    text = text.replace("## Content locations\n", section + "## Content locations\n", 1)
    text = text.replace(
        "- [`docs/BOSS_PLAYTEST_CHECKLIST.md`](docs/BOSS_PLAYTEST_CHECKLIST.md) for the complete manual boss encounter review;",
        "- [`docs/BOSS_PLAYTEST_CHECKLIST.md`](docs/BOSS_PLAYTEST_CHECKLIST.md) for the complete manual boss encounter review;\n- [`docs/CINEMATIC_TIMELINE_STUDIO.md`](docs/CINEMATIC_TIMELINE_STUDIO.md) for timeline steps, triggers, skip equivalence and save-safety rules;\n- [`docs/CINEMATIC_PLAYTEST_CHECKLIST.md`](docs/CINEMATIC_PLAYTEST_CHECKLIST.md) for the complete manual cinematic review;",
        1,
    )
    text = text.replace("all eleven editor plugins", "all twelve editor plugins")
    text = text.replace(
        "26. malformed boss arena, phase, pattern, reward and reinforcement rejection tests.",
        "26. malformed boss arena, phase, pattern, reward and reinforcement rejection tests;\n27. executable cinematic playback, camera, dialogue, skip-equivalence and durable-completion tests;\n28. executable Cinematic & Timeline Studio editor-state and rollback tests;\n29. malformed cinematic map, era, target, effect and checkpoint rejection tests.",
        1,
    )
    text = text.replace(
        "- Boss encounters that preserve readable timing, required phases, safe arena exits and durable one-time outcomes",
        "- Boss encounters that preserve readable timing, required phases, safe arena exits and durable one-time outcomes\n- Cinematics that remain skippable, text-readable and progression-equivalent without serialising transient presentation state",
        1,
    )
    text = text.replace(
        "- [`docs/BOSS_PLAYTEST_CHECKLIST.md`](docs/BOSS_PLAYTEST_CHECKLIST.md): manual boss fairness, controller and durability review",
        "- [`docs/BOSS_PLAYTEST_CHECKLIST.md`](docs/BOSS_PLAYTEST_CHECKLIST.md): manual boss fairness, controller and durability review\n- [`docs/CINEMATIC_TIMELINE_STUDIO.md`](docs/CINEMATIC_TIMELINE_STUDIO.md): cinematic timeline, trigger and save-safety production rules\n- [`docs/CINEMATIC_PLAYTEST_CHECKLIST.md`](docs/CINEMATIC_PLAYTEST_CHECKLIST.md): manual cinematic pacing, skip and durability review",
        1,
    )
    text = text.replace(
        "alternate ammunition, merchant restocking and regional scarcity, cinematics, campaign packaging",
        "alternate ammunition, merchant restocking and regional scarcity, campaign packaging",
        1,
    )
    readme.write_text(text, encoding="utf-8", newline="\n")

for helper in [
    Path(".github/workflows/apply-cinematic-integration.yml"),
    Path("tools/apply_cinematic_integration.py"),
]:
    if helper.exists():
        helper.unlink()
