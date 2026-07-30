extends SceneTree

const CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")
const CinematicValidator = preload("res://src/content/cinematic_validator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	run_validation_edges()
	finish()


func run_validation_edges() -> void:
	var catalog := {
		"schema_version": CinematicCatalog.SUPPORTED_SCHEMA,
		"cinematics": [
			{
				"id": "bad_sequence",
				"display_name": "Bad Sequence",
				"map_id": "missing_map",
				"available_eras": ["future"],
				"skippable": "yes",
				"letterbox": true,
				"trigger_once": true,
				"completion_state_key": "",
				"steps": [
					{"id": "camera", "type": "camera", "target": "placement:missing", "zoom": 5.0, "duration": 0.5},
					{"id": "camera", "type": "move_actor", "actor": "unknown", "position": {}, "duration": 0.0},
					{"id": "era", "type": "set_era", "era_id": "future"},
					{"id": "fade", "type": "fade", "direction": "sideways", "duration": 0.0},
					{"id": "effects", "type": "effects", "effects": [
						{"type": "grant_item", "item_id": "missing_item", "quantity": 0},
						{"type": "grant_currency", "currency_id": "missing_currency", "amount": -1},
						{"type": "unknown_effect"}
					]},
					{"id": "checkpoint", "type": "checkpoint", "key": ""}
				],
				"completion_effects": "not-an-array",
				"skip_effects": []
			}
		]
	}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var state_keys: Dictionary = {}
	CinematicValidator.validate_catalog_file(
		catalog,
		"bad_catalog.json",
		{"first_crossing": {"id": "first_crossing"}},
		{"first_crossing": {"verdant": true}},
		{"first_crossing": {"known_actor": true}},
		{"known_item": {}},
		{"known_recipe": {}},
		{"known_quest": {}},
		{"known_currency": {}},
		state_keys,
		errors,
		warnings
	)
	check(contains_fragment(errors, "not a declared map"), "Unknown cinematic maps must be rejected.")
	check(contains_fragment(errors, "skippable must be boolean"), "Non-boolean skip policy must be rejected.")
	check(contains_fragment(errors, "require completion_state_key"), "Trigger-once sequences without a completion key must be rejected.")
	check(contains_fragment(errors, "duplicate step id"), "Duplicate timeline step IDs must be rejected.")
	check(contains_fragment(errors, "unsupported camera target") or contains_fragment(errors, "unknown placement target"), "Unknown camera targets must be rejected.")
	check(contains_fragment(errors, "zoom must be between"), "Unsafe cinematic zoom must be rejected.")
	check(contains_fragment(errors, "actor must be"), "Unknown actor targets must be rejected.")
	check(contains_fragment(errors, "move_actor duration"), "Zero-duration actor blocking must be rejected.")
	check(contains_fragment(errors, "fade direction"), "Unsupported fade directions must be rejected.")
	check(contains_fragment(errors, "unknown item"), "Unknown cinematic item rewards must be rejected.")
	check(contains_fragment(errors, "unknown currency"), "Unknown cinematic currency effects must be rejected.")
	check(contains_fragment(errors, "unsupported effect type"), "Unsupported cinematic effects must be rejected.")
	check(contains_fragment(errors, "checkpoint key"), "Empty cinematic checkpoints must be rejected.")
	check(contains_fragment(errors, "completion_effects must be an array"), "Malformed completion effects must be rejected.")

	var duplicate_catalog := CinematicCatalog.default_catalog()
	var duplicate := (duplicate_catalog.get("cinematics", []) as Array)[0].duplicate(true)
	(duplicate_catalog.get("cinematics", []) as Array).append(duplicate)
	errors.clear()
	warnings.clear()
	CinematicValidator.validate_catalog_file(
		duplicate_catalog,
		"duplicate_catalog.json",
		{"first_crossing": {"id": "first_crossing"}},
		{"first_crossing": {"verdant": true, "ashen": true}},
		{"first_crossing": {}},
		{},
		{},
		{},
		{},
		{},
		errors,
		warnings
	)
	check(contains_fragment(errors, "duplicate cinematic id"), "Duplicate cinematic IDs must be rejected.")
	check(contains_fragment(errors, "also used"), "Duplicate completion-state keys must be rejected.")


func contains_fragment(messages: Variant, fragment: String) -> bool:
	if typeof(messages) != TYPE_ARRAY:
		return false
	for message in messages:
		if fragment.to_lower() in str(message).to_lower():
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Cinematic validation edge smoke test passed: malformed maps, steps, targets, effects and completion keys are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
