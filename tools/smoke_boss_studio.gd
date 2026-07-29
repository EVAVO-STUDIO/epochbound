extends SceneTree

const BossStudio = preload("res://addons/epochbound_boss_studio/boss_studio.gd")
const BossValidator = preload("res://src/content/boss_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := BossStudio.new()
	root.add_child(studio)
	check(studio != null, "Boss Studio must instantiate.")
	if studio == null:
		finish()
		return

	var campaign_selector_value: Variant = studio.get("campaign_selector")
	var boss_list_value: Variant = studio.get("boss_list")
	var arena_selector_value: Variant = studio.get("arena_zone_selector")
	var connection_list_value: Variant = studio.get("connection_list")
	var phases_edit_value: Variant = studio.get("phases_edit")
	var defeat_effects_value: Variant = studio.get("defeat_effects_edit")
	var phase_summary_value: Variant = studio.get("phase_summary")
	check(campaign_selector_value is OptionButton, "Boss Studio must create a campaign selector.")
	check(boss_list_value is ItemList, "Boss Studio must create an enemy definition list.")
	check(arena_selector_value is OptionButton, "Boss Studio must create an arena selector.")
	check(connection_list_value is ItemList, "Boss Studio must create a connection-lock selector.")
	check(phases_edit_value is TextEdit, "Boss Studio must preserve phases as complete JSON-line records.")
	check(defeat_effects_value is TextEdit, "Boss Studio must preserve defeat effects as complete JSON-line records.")
	check(phase_summary_value is ItemList, "Boss Studio must create a phase and fairness preview.")
	if campaign_selector_value is OptionButton:
		check((campaign_selector_value as OptionButton).item_count >= 1, "Boss Studio must discover the reference campaign.")
	if boss_list_value is ItemList:
		check((boss_list_value as ItemList).item_count == 2, "Reference object catalogue must expose the Ash Hound and Underworks Sentinel as enemy definitions.")
		select_item_metadata(boss_list_value, "underworks_sentinel")
		studio.call("on_boss_selected", (boss_list_value as ItemList).get_selected_items()[0])

	check(str(studio.get("selected_object_id")) == "underworks_sentinel", "Boss Studio must select the reference Sentinel.")
	var enabled_value: Variant = studio.get("boss_enabled")
	check(enabled_value is CheckBox and (enabled_value as CheckBox).button_pressed, "Reference Sentinel must load with its boss contract enabled.")
	if arena_selector_value is OptionButton:
		check(selected_option_metadata(arena_selector_value) == "underworks_gallery_watch", "Boss Studio must resolve the Sentinel arena zone.")
	if connection_list_value is ItemList:
		check((connection_list_value as ItemList).item_count == 1, "Underworks source map must expose one lockable exit.")
		check((connection_list_value as ItemList).is_selected(0), "Reference boss contract must lock the Underworks exit.")
	if phases_edit_value is TextEdit:
		var text := (phases_edit_value as TextEdit).text
		check("catalogue_measure" in text, "Boss Studio must preserve the Verdant opening phase.")
		check("cinder_measure" in text, "Boss Studio must preserve the Ashen opening phase.")
		check("last_accession" in text, "Boss Studio must preserve the final shared phase.")
	if phase_summary_value is ItemList:
		check((phase_summary_value as ItemList).item_count == 3, "Phase preview must expose all three reference phases.")

	var valid_phase: Variant = studio.call(
		"parse_json_lines",
		'{"id":"test_phase","display_name":"Test Phase","health_ratio_at_or_below":1.0,"available_eras":[],"attack_windup":0.5,"attack_pattern":[{"type":"aimed_shot","count":1},{"type":"pause","duration":0.5}],"reinforcement_placements":[]}',
		"test phase"
	)
	check(typeof(valid_phase) == TYPE_DICTIONARY and bool((valid_phase as Dictionary).get("ok", false)), "Boss Studio must parse complete phase JSON records.")
	var malformed: Variant = studio.call("parse_json_lines", "not-json", "test phase")
	check(typeof(malformed) == TYPE_DICTIONARY and not bool((malformed as Dictionary).get("ok", true)), "Boss Studio must reject malformed phase source.")

	var validation := BossValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Boss Studio reference campaign must pass complete validation.")
	check(int(validation.get("boss_count", 0)) == 1, "Reference campaign must expose one boss definition.")
	check(int(validation.get("boss_phase_count", 0)) == 3, "Reference boss must expose three phases.")
	check(int(validation.get("boss_reinforcement_count", 0)) == 2, "Reference final phase must expose two reinforcements.")

	root.remove_child(studio)
	studio.free()
	finish()


func select_item_metadata(list: ItemList, requested: String) -> void:
	for index in range(list.item_count):
		if str(list.get_item_metadata(index)) == requested:
			list.select(index)
			return


func selected_option_metadata(value: Variant) -> String:
	if not value is OptionButton:
		return ""
	var option := value as OptionButton
	if option.item_count == 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func finish() -> void:
	if failures.is_empty():
		print("Boss Studio smoke test passed: campaigns, enemy selection, arena locks, phase source, fairness preview and complete validation are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
