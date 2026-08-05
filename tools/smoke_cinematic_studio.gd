extends SceneTree

const CinematicStudio = preload("res://addons/epochbound_cinematic_studio/cinematic_studio.gd")
const Repository = preload("res://src/content/campaign_repository.gd")
const CinematicValidator = preload("res://src/content/cinematic_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := CinematicStudio.new()
	root.add_child(studio)
	var campaign_selector_value: Variant = studio.get("campaign_selector")
	var cinematic_list_value: Variant = studio.get("cinematic_list")
	var map_selector_value: Variant = studio.get("map_selector")
	var steps_edit_value: Variant = studio.get("steps_edit")
	var timeline_list_value: Variant = studio.get("timeline_list")
	check(campaign_selector_value is OptionButton, "Cinematic Studio must create a campaign selector.")
	check(cinematic_list_value is ItemList, "Cinematic Studio must create a cinematic list.")
	check(map_selector_value is OptionButton, "Cinematic Studio must create a map selector.")
	check(steps_edit_value is TextEdit, "Cinematic Studio must create a timeline source editor.")
	check(timeline_list_value is ItemList, "Cinematic Studio must create a timeline preview.")
	if campaign_selector_value is OptionButton:
		check((campaign_selector_value as OptionButton).item_count >= 1, "Cinematic Studio must discover the reference campaign.")
	if cinematic_list_value is ItemList:
		check((cinematic_list_value as ItemList).item_count == 3, "Reference campaign must expose three cinematics in the editor.")
	if map_selector_value is OptionButton:
		check((map_selector_value as OptionButton).item_count == 3, "Cinematic map selector must expose all three reference maps.")

	studio.call("select_cinematic_id", "storm_door_opening")
	check(str(studio.get("selected_cinematic_id")) == "storm_door_opening", "Editor must select a stable cinematic ID.")
	var completion_key_value: Variant = studio.get("completion_key_edit")
	if completion_key_value is LineEdit:
		check((completion_key_value as LineEdit).text == "cinematic:storm_door_opening", "Editor must preserve the authored completion key.")
	if timeline_list_value is ItemList:
		check((timeline_list_value as ItemList).item_count == 7, "Timeline preview must expose all opening steps.")

	var valid: Variant = studio.call("parse_json_lines", '{"id":"wait","type":"wait","duration":0.5}\n{"id":"line","type":"dialogue","text":"Hello","advance_on_confirm":true}', "test timeline")
	check(typeof(valid) == TYPE_DICTIONARY and bool((valid as Dictionary).get("ok", false)), "Editor must parse valid JSON-line steps.")
	if typeof(valid) == TYPE_DICTIONARY:
		check((valid as Dictionary).get("entries", []).size() == 2, "Timeline parser must retain complete step records.")
	var malformed: Variant = studio.call("parse_json_lines", "not-json", "test timeline")
	check(typeof(malformed) == TYPE_DICTIONARY and not bool((malformed as Dictionary).get("ok", true)), "Editor must reject malformed timeline source.")

	var catalog_path := str(studio.get("active_catalog_path"))
	var source_snapshot := read_source_text(catalog_path)
	check(bool(source_snapshot.get("ok", false)), "Rollback test must snapshot the exact cinematic source bytes.")
	var before_result := Repository.read_json(catalog_path)
	check(bool(before_result.get("ok", false)), "Rollback test must read the valid cinematic catalog.")
	var invalid_catalog: Dictionary = (studio.get("active_catalog") as Dictionary).duplicate(true)
	for index in range((invalid_catalog.get("cinematics", []) as Array).size()):
		var sequence: Dictionary = (invalid_catalog.get("cinematics", []) as Array)[index]
		if str(sequence.get("id", "")) == "storm_door_opening":
			sequence["map_id"] = "missing_map"
			(invalid_catalog.get("cinematics", []) as Array)[index] = sequence
	studio.set("active_catalog", invalid_catalog)
	check(not bool(studio.call("save_catalog_transactional")), "Invalid cinematic edits must be rejected and rolled back.")
	var restored_result := Repository.read_json(catalog_path)
	check(bool(restored_result.get("ok", false)), "Rejected cinematic edit must leave a readable catalog.")
	var restored_map := ""
	for value in (restored_result.get("data", {}) as Dictionary).get("cinematics", []):
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == "storm_door_opening":
			restored_map = str((value as Dictionary).get("map_id", ""))
	check(restored_map == "bellweather_crossing", "Rollback must restore the prior cinematic map reference.")
	check(
		restore_source_text(catalog_path, str(source_snapshot.get("text", ""))),
		"Cinematic rollback regression must restore the exact original source bytes."
	)
	var exact_restore := read_source_text(catalog_path)
	check(
		bool(exact_restore.get("ok", false))
		and str(exact_restore.get("text", "")) == str(source_snapshot.get("text", "")),
		"Cinematic rollback regression must leave the tracked catalogue byte-for-byte unchanged."
	)

	var validation := CinematicValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must remain valid after editor rollback.")

	root.remove_child(studio)
	studio.free()
	finish()


func read_source_text(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "text": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "text": ""}
	return {"ok": true, "text": file.get_as_text()}


func restore_source_text(path: String, text: String) -> bool:
	if path.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	return true


func finish() -> void:
	if failures.is_empty():
		print("Cinematic Studio smoke test passed: campaigns, timelines, source parsing, preview, transactional rollback and exact source isolation are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
