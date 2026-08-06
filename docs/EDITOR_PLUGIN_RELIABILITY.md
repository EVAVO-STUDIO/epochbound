# Editor Plugin Reliability

Epochbound exposes seventeen connected main-screen editor plugins. Their tabs must remain readable and warning-free across the exact supported Godot editor rather than depending on an unchecked theme item name.

## Shared icon contract

Every plugin routes `_get_plugin_icon()` through:

```text
res://addons/epochbound_editor_common/editor_plugin_icon.gd
```

Each plugin supplies an ordered list of semantic icon candidates. The resolver:

1. obtains the active editor theme from `EditorInterface`;
2. ignores empty candidate names;
3. checks `Theme.has_icon()` before any `Theme.get_icon()` call;
4. returns the first available semantic candidate;
5. falls back to the stable `Node` editor icon;
6. returns `null` quietly only when the editor theme itself cannot provide a safe icon.

The resolver never probes a missing theme item through `get_icon()`. This prevents Godot's `Trying to access a non-existing editor theme icon` warning while allowing a plugin to keep a more specific first choice when that icon exists.

## Plugin ownership

The static runtime-composition contract discovers all `addons/epochbound_*/plugin.gd` entrypoints and requires exactly seventeen. Every plugin must:

- extend `EditorPlugin`;
- preload the shared icon resolver;
- declare ordered `ICON_CANDIDATES`;
- call the shared resolver from `_get_plugin_icon()`;
- avoid direct `get_icon()` and `get_theme_icon()` calls;
- release its main-screen control and clear the retained `studio` reference during `_exit_tree()`;
- remain enabled through its `plugin.cfg` entry in `project.godot`.

A new authoring tool is not complete until it joins this contract.

## Validation

`tools/smoke_editor_plugin_icons.gd` proves deterministic semantic selection, blank filtering, stable fallback and quiet failure with synthetic `Theme` resources.

`tools/compile_probe.gd` directly loads both the resolver and its smoke test. `scripts/validate.ps1` runs the smoke test and also fails the complete gate if any Godot process logs the missing-editor-icon warning. The normal headless import therefore validates the actual Godot 4.6.2 editor theme, while the synthetic smoke test proves the resolver's edge behaviour.

The static `tools/check_runtime_scene_contract.py` gate pins all seventeen plugin entrypoints, the shared resolver, the smoke test, project enablement and the absence of unchecked theme-icon lookups before Godot execution begins.

## Scope boundary

This contract governs editor-tab icon lookup and plugin teardown ownership. It does not replace visual QA of the editor screens themselves, custom campaign art, operating-system application icons or final game branding assets.
