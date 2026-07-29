extends SceneTree

const CampaignValidator = preload("res://src/content/campaign_validator.gd")

func _initialize() -> void:
	var report := CampaignValidator.validate_all()
	for warning in report.get("warnings", []):
		print_rich("[color=yellow]WARNING[/color] %s" % warning)
	for error in report.get("errors", []):
		push_error(String(error))
	print(
		"Campaign validation: %d campaign(s), %d map(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 0),
			report.get("map_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	quit(0 if report.get("ok", false) else 1)
