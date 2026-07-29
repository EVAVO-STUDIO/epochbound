extends SceneTree

const CompanionValidator = preload("res://src/content/companion_validator.gd")


func _initialize() -> void:
	var report := CompanionValidator.validate_all()
	for warning in report.get("warnings", []):
		print_rich("[color=yellow]WARNING[/color] %s" % warning)
	for error in report.get("errors", []):
		push_error(str(error))
	print(
		"Content validation: %d campaign(s), %d map(s), %d definition(s), %d placement(s), %d encounter zone(s), %d companion cue(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 0),
			report.get("map_count", 0),
			report.get("definition_count", 0),
			report.get("placement_count", 0),
			report.get("zone_count", 0),
			report.get("cue_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	quit(0 if report.get("ok", false) else 1)
