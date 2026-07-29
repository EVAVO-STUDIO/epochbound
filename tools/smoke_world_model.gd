extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/campaign_validator.gd")
const MapModel = preload("res://src/content/map_model.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	var validation := Validator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass full validation.")
	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign JSON must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	check(campaign.get("map_files", []).size() == 2, "Reference campaign must declare two maps.")

	var bell_path := Repository.find_exact_map_path(CAMPAIGN_PATH, campaign, "bellweather_crossing")
	var clock_path := Repository.find_exact_map_path(CAMPAIGN_PATH, campaign, "clockwood_edge")
	check(not bell_path.is_empty(), "Bellweather map path must resolve exactly.")
	check(not clock_path.is_empty(), "Clockwood map path must resolve exactly.")
	var bell_result := Repository.read_json(bell_path)
	var clock_result := Repository.read_json(clock_path)
	check(bell_result.get("ok", false), "Bellweather map must load.")
	check(clock_result.get("ok", false), "Clockwood map must load.")
	var bell: Dictionary = bell_result.get("data", {})
	var clock: Dictionary = clock_result.get("data", {})

	var collision_point := MapModel.cell_to_world(bell, Vector2i(7, 12))
	var open_point := MapModel.cell_to_world(bell, Vector2i(20, 13))
	var water_point := MapModel.cell_to_world(bell, Vector2i(17, 16))
	var ashen_cliff := MapModel.cell_to_world(bell, Vector2i(24, 11))
	check(MapModel.is_position_blocked(bell, collision_point, "verdant", 2.0), "Authored collision cells must block movement.")
	check(not MapModel.is_position_blocked(bell, open_point, "verdant", 2.0), "Authored path cells must remain walkable.")
	check(MapModel.is_position_blocked(bell, water_point, "verdant", 2.0), "Blocked terrain definitions must block movement.")
	check(not MapModel.is_position_blocked(bell, ashen_cliff, "verdant", 2.0), "Era-scoped terrain must not leak into other eras.")
	check(MapModel.is_position_blocked(bell, ashen_cliff, "ashen", 2.0), "Era-scoped terrain must apply in its declared era.")

	var connection := MapModel.find_connection_near(bell, Vector2(512, 216), "verdant", "interact")
	check(String(connection.get("target_map", "")) == "clockwood_edge", "Bellweather connection must target Clockwood.")
	var target_entry := MapModel.find_entry_point(clock, String(connection.get("target_entry", "")), "verdant")
	check(String(target_entry.get("id", "")) == "from_bellweather", "Clockwood target entry must resolve.")

	var navigation_start := MapModel.cell_to_world(bell, Vector2i(6, 13))
	var navigation_target := MapModel.cell_to_world(bell, Vector2i(10, 13))
	var navigation_step := MapModel.navigation_step(bell, navigation_start, navigation_target, "verdant")
	check(navigation_step.x > navigation_start.x, "Navigation should advance toward a connected target cell.")
	var recovery := MapModel.nearest_recovery_point(bell, Vector2(500, 230), "verdant", Vector2.ZERO)
	check(recovery.distance_to(Vector2(448, 232)) < 2.0, "Nearest authored recovery anchor should be selected.")

	if failures.is_empty():
		print("World-model smoke test passed: terrain, collision, navigation, recovery and map links are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
