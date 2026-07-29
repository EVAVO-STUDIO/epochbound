extends SceneTree

const StoryValidator = preload("res://src/content/story_validator.gd")


func _initialize() -> void:
	var report := StoryValidator.validate_all()
	for warning in report.get("warnings", []):
		print_rich("[color=yellow]WARNING[/color] %s" % warning)
	for error in report.get("errors", []):
		push_error(str(error))
	print(
		"Content validation: %d campaign(s), %d map(s), %d definition(s), %d placement(s), %d encounter zone(s), %d companion cue(s), %d item(s), %d recipe(s), %d conversation(s), %d quest(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 0),
			report.get("map_count", 0),
			report.get("definition_count", 0),
			report.get("placement_count", 0),
			report.get("zone_count", 0),
			report.get("cue_count", 0),
			report.get("item_count", 0),
			report.get("recipe_count", 0),
			report.get("conversation_count", 0),
			report.get("quest_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	quit(0 if report.get("ok", false) else 1)
