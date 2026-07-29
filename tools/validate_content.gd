extends SceneTree

const EconomyValidator = preload("res://src/content/economy_validator.gd")


func _initialize() -> void:
	var report: Dictionary = EconomyValidator.validate_all()
	for warning in report.get("warnings", []):
		print_rich("[color=yellow]WARNING[/color] %s" % warning)
	for error in report.get("errors", []):
		push_error(str(error))
	print(
		"Content validation: %d campaign(s), %d map(s), %d object definition(s), %d placement(s), %d encounter zone(s), %d companion cue(s), %d item(s), %d recipe(s), %d conversation(s), %d quest(s), %d save policy record(s), %d equipment item(s), %d equipment slot(s), %d capability definition(s), %d capability gate(s), %d currency definition(s), %d merchant(s), %d merchant binding(s), %d stock entry(s), %d warning(s), %d error(s)." % [
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
			report.get("save_policy_count", 0),
			report.get("equipment_item_count", 0),
			report.get("equipment_slot_count", 0),
			report.get("capability_count", 0),
			report.get("capability_gate_count", 0),
			report.get("currency_count", 0),
			report.get("merchant_count", 0),
			report.get("merchant_binding_count", 0),
			report.get("merchant_stock_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	quit(0 if bool(report.get("ok", false)) else 1)
