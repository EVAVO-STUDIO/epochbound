extends "res://src/cinematic_runtime.gd"


func presentation_overlay_handles_combat_readability() -> bool:
	var overlay := get_node_or_null("PresentationLayer/PresentationOverlay")
	return overlay != null and overlay.has_method("combat_readability_contract_ok")


func draw_projectiles() -> void:
	# Projectiles are redrawn in the high presentation CanvasLayer so they share
	# camera conversion and feet-based ordering with actors and world entities.
	if presentation_overlay_handles_combat_readability():
		return
	super.draw_projectiles()


func draw_active_boss_arena() -> void:
	# The presentation layer owns the arena frame when available. Retain the
	# inherited fallback for stripped-down or custom scenes without that layer.
	if presentation_overlay_handles_combat_readability():
		return
	super.draw_active_boss_arena()
