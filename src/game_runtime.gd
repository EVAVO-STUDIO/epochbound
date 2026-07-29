extends "res://src/app.gd"

# The scene entrypoint keeps restart ordering explicit: select the campaign's
# starting era first, then resolve spawns and recovery against that era.
func begin_game() -> void:
	current_era_id = String(campaign.get("start_era", first_era_id()))
	if current_era_id.is_empty():
		current_era_id = first_era_id()
	reset_actor_positions()
	shift_lock = 0.0
	transition_lock = 0.0
	change_flow(Flow.GAME)
