@tool
extends RefCounted

const PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")

const CURRENT_SCHEMA := 2


static func default_settings() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA,
		"master_volume": 1.0,
		"music_volume": 1.0,
		"ambience_volume": 1.0,
		"sfx_volume": 1.0,
		"screen_texture_intensity": 1.0,
		"camera_shake_intensity": 1.0,
		"environment_motion_intensity": 1.0,
		"flash_intensity": 1.0,
		"show_action_prompts": true,
		"high_contrast_ui": false,
		"input_bindings": PlayerInputBindings.default_profile()
	}


static func entries() -> Array:
	return [
		{"id": "master_volume", "label": "MASTER VOLUME", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.1},
		{"id": "music_volume", "label": "MUSIC", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.1},
		{"id": "ambience_volume", "label": "AMBIENCE", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.1},
		{"id": "sfx_volume", "label": "SOUND EFFECTS", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.1},
		{"id": "screen_texture_intensity", "label": "SCREEN TEXTURE", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.25},
		{"id": "camera_shake_intensity", "label": "CAMERA SHAKE", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.25},
		{"id": "environment_motion_intensity", "label": "WORLD MOTION", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.25},
		{"id": "flash_intensity", "label": "SCREEN FLASHES", "kind": "range", "minimum": 0.0, "maximum": 1.0, "step": 0.25},
		{"id": "show_action_prompts", "label": "ACTION PROMPTS", "kind": "boolean"},
		{"id": "high_contrast_ui", "label": "HIGH CONTRAST UI", "kind": "boolean"},
		{"id": "controls", "label": "CONTROLS", "kind": "action"},
		{"id": "reset_defaults", "label": "RESET ALL DEFAULTS", "kind": "action"},
		{"id": "back", "label": "BACK", "kind": "action"}
	]


static func entry(entry_id: String) -> Dictionary:
	for value in entries():
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == entry_id:
			return (value as Dictionary).duplicate(true)
	return {}


static func sanitize(value: Variant) -> Dictionary:
	var output := default_settings()
	if typeof(value) != TYPE_DICTIONARY:
		return output
	var source: Dictionary = value
	for raw_definition in entries():
		if typeof(raw_definition) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = raw_definition
		var setting_id := str(definition.get("id", ""))
		var kind := str(definition.get("kind", ""))
		if not source.has(setting_id):
			continue
		var raw: Variant = source.get(setting_id)
		if kind == "range" and typeof(raw) in [TYPE_INT, TYPE_FLOAT]:
			var minimum := float(definition.get("minimum", 0.0))
			var maximum := float(definition.get("maximum", 1.0))
			var step := maxf(0.001, float(definition.get("step", 0.1)))
			output[setting_id] = clampf(snappedf(float(raw), step), minimum, maximum)
		elif kind == "boolean" and typeof(raw) == TYPE_BOOL:
			output[setting_id] = bool(raw)
	output["input_bindings"] = PlayerInputBindings.sanitize_profile(source.get("input_bindings", PlayerInputBindings.default_profile()))
	output["schema_version"] = CURRENT_SCHEMA
	return output


static func validate(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Player settings root must be an object."]}
	var source: Dictionary = value
	var schema_value: Variant = source.get("schema_version", 0)
	if typeof(schema_value) != TYPE_INT:
		errors.append("Player settings schema_version must be an integer.")
	elif int(schema_value) < 0 or int(schema_value) > CURRENT_SCHEMA:
		errors.append("Player settings schema %d is unsupported." % int(schema_value))
	for raw_definition in entries():
		if typeof(raw_definition) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = raw_definition
		var setting_id := str(definition.get("id", ""))
		var kind := str(definition.get("kind", ""))
		if kind == "action" or not source.has(setting_id):
			continue
		var raw: Variant = source.get(setting_id)
		if kind == "range":
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
				errors.append("Player setting '%s' must be numeric." % setting_id)
				continue
			var minimum := float(definition.get("minimum", 0.0))
			var maximum := float(definition.get("maximum", 1.0))
			if float(raw) < minimum or float(raw) > maximum:
				errors.append("Player setting '%s' must be between %.2f and %.2f." % [setting_id, minimum, maximum])
		elif kind == "boolean" and typeof(raw) != TYPE_BOOL:
			errors.append("Player setting '%s' must be boolean." % setting_id)
	if source.has("input_bindings"):
		var binding_validation := PlayerInputBindings.validate_profile(source.get("input_bindings"))
		for message in binding_validation.get("errors", []):
			errors.append(str(message))
	return {"ok": errors.is_empty(), "errors": errors}


static func migrate(value: Variant) -> Dictionary:
	var validation := validate(value)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "settings": {}, "migrated": false, "from_version": -1, "errors": validation.get("errors", [])}
	var source: Dictionary = value
	var from_version := int(source.get("schema_version", 0))
	var migrated := from_version != CURRENT_SCHEMA
	for raw_definition in entries():
		if typeof(raw_definition) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = raw_definition
		if str(definition.get("kind", "")) == "action":
			continue
		if not source.has(str(definition.get("id", ""))):
			migrated = true
	if not source.has("input_bindings"):
		migrated = true
	return {"ok": true, "settings": sanitize(source), "migrated": migrated, "from_version": from_version, "errors": []}


static func number(settings: Dictionary, setting_id: String, fallback: float = 1.0) -> float:
	var value: Variant = sanitize(settings).get(setting_id, fallback)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else fallback


static func boolean(settings: Dictionary, setting_id: String, fallback: bool = false) -> bool:
	var value: Variant = sanitize(settings).get(setting_id, fallback)
	return bool(value) if typeof(value) == TYPE_BOOL else fallback


static func input_bindings(settings: Dictionary) -> Dictionary:
	var value: Variant = sanitize(settings).get("input_bindings", PlayerInputBindings.default_profile())
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else PlayerInputBindings.default_profile()


static func adjusted(settings: Dictionary, setting_id: String, direction: int) -> Dictionary:
	var output := sanitize(settings)
	var definition := entry(setting_id)
	if definition.is_empty() or direction == 0:
		return output
	var kind := str(definition.get("kind", ""))
	if kind == "range":
		var minimum := float(definition.get("minimum", 0.0))
		var maximum := float(definition.get("maximum", 1.0))
		var step := maxf(0.001, float(definition.get("step", 0.1)))
		var resolved_direction := 1 if direction > 0 else -1
		output[setting_id] = clampf(snappedf(number(output, setting_id, minimum) + step * resolved_direction, step), minimum, maximum)
	elif kind == "boolean":
		output[setting_id] = not boolean(output, setting_id, false)
	return output


static func value_text(settings: Dictionary, setting_id: String) -> String:
	var kind := str(entry(setting_id).get("kind", ""))
	if kind == "range":
		return "%d%%" % int(round(number(settings, setting_id, 0.0) * 100.0))
	if kind == "boolean":
		return "ON" if boolean(settings, setting_id, false) else "OFF"
	return ""


static func rows(settings: Dictionary) -> Array:
	var output: Array = []
	for raw_definition in entries():
		if typeof(raw_definition) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = (raw_definition as Dictionary).duplicate(true)
		definition["value"] = value_text(settings, str(definition.get("id", "")))
		output.append(definition)
	return output
