from pathlib import Path

runtime = Path("src/cinematic_runtime.gd")
text = runtime.read_text(encoding="utf-8")
text = text.replace(
    "cinematic_definitions = definitions_from_catalog(CinematicCatalog.default_catalog())",
    "cinematic_definitions = definitions_from_cinematic_catalog(CinematicCatalog.default_catalog())",
)
text = text.replace(
    "func definitions_from_catalog(catalog: Dictionary) -> Dictionary:",
    "func definitions_from_cinematic_catalog(catalog: Dictionary) -> Dictionary:",
)
runtime.write_text(text, encoding="utf-8", newline="\n")

studio_test = Path("tools/smoke_cinematic_studio.gd")
text = studio_test.read_text(encoding="utf-8")
text = text.replace(
    "\tvar valid := studio.call(",
    "\tvar valid: Variant = studio.call(",
)
text = text.replace(
    "\tvar malformed := studio.call(",
    "\tvar malformed: Variant = studio.call(",
)
studio_test.write_text(text, encoding="utf-8", newline="\n")

edge_test = Path("tools/smoke_cinematic_validation_edges.gd")
text = edge_test.read_text(encoding="utf-8")
text = text.replace(
    'var duplicate := (duplicate_catalog.get("cinematics", []) as Array)[0].duplicate(true)',
    'var duplicate: Dictionary = ((duplicate_catalog.get("cinematics", []) as Array)[0] as Dictionary).duplicate(true)',
)
edge_test.write_text(text, encoding="utf-8", newline="\n")

Path("tools/fix_cinematic_compile.py").unlink()
