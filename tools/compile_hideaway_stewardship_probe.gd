extends SceneTree

const MODEL := preload("res://src/game/hideaway_stewardship.gd")
const VALIDATOR := preload("res://src/content/hideaway_stewardship_validator.gd")
const SMOKE := preload("res://tools/smoke_hideaway_stewardship.gd")


func _init() -> void:
	var state: Dictionary = MODEL.default_state(0.0)
	var errors: PackedStringArray = MODEL.validate_state(state)
	if not errors.is_empty():
		push_error("Archive Hideaway compile probe default state failed: %s" % [errors])
		quit(1)
		return
	var definition: Dictionary = VALIDATOR.load_reference_definition()
	errors = VALIDATOR.validate_definition(definition)
	if not errors.is_empty():
		push_error("Archive Hideaway compile probe definition failed: %s" % [errors])
		quit(1)
		return
	if SMOKE == null:
		push_error("Archive Hideaway smoke script failed to preload")
		quit(1)
		return
	print("Archive Hideaway stewardship compile probe passed: deterministic active-play expeditions, bounded return opportunities, four refuge facilities, preparation charges and strict reference data load cleanly.")
	quit(0)
