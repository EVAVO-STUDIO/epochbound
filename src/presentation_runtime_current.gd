extends "res://src/cinematic_runtime.gd"


func presentation_overlay_handles_combat_readability() -> bool:
	var overlay := get_node_or_null("PresentationLayer/PresentationOverlay")
	return overlay != null and overlay.has_method("combat_readability_contract_ok")


func root_presentation_suppression_contract_ok() -> bool:
	var overlay := get_node_or_null("PresentationLayer/PresentationOverlay")
	return (
		presentation_overlay_handles_combat_readability()
		and overlay != null
		and overlay.has_method("draw_adventure_hud")
		and overlay.has_method("draw_boss_banner_overlay")
		and overlay.has_method("draw_projectile_overlay")
	)


func draw_game() -> void:
	if not presentation_overlay_handles_combat_readability():
		super.draw_game()
		return
	# The inherited Boss runtime draws its banner after the world. The higher
	# CanvasLayer owns that banner in the production scene, so temporarily hide
	# only the root copy while preserving the durable banner state.
	var preserved_banner := boss_banner
	boss_banner = ""
	super.draw_game()
	boss_banner = preserved_banner


func draw_hud(era_data: Dictionary) -> void:
	# The production CanvasLayer owns the complete adventure, ammunition and boss
	# HUD. Stripped-down custom scenes without that layer retain inherited HUDs.
	if presentation_overlay_handles_combat_readability():
		return
	super.draw_hud(era_data)


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
