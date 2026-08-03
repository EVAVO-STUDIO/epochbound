extends SceneTree

const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")
const SaveStateStudio = preload("res://addons/epochbound_save_state_studio/save_state_studio_supply.gd")

const CAMPAIGN_ID := "epochbound_demo"
const SLOT_ID := "slot_1"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	var profile := test_profile()
	var write_result: Dictionary = SaveProfileStore.write_profile(profile)
	check(bool(write_result.get("ok", false)), "Editor smoke test profile must write successfully.")

	var studio := SaveStateStudio.new()
	root.add_child(studio)
	var campaign_selector_value: Variant = studio.get("campaign_selector")
	var slot_list_value: Variant = studio.get("slot_list")
	var overview_value: Variant = studio.get("overview")
	var inventory_list_value: Variant = studio.get("inventory_list")
	var equipment_list_value: Variant = studio.get("equipment_list")
	var loaded_ammo_list_value: Variant = studio.get("loaded_ammo_list")
	var supply_cycle_list_value: Variant = studio.get("supply_cycle_list")
	var quest_list_value: Variant = studio.get("quest_list")
	var state_list_value: Variant = studio.get("state_list")
	var raw_text_value: Variant = studio.get("raw_text")
	var delete_confirmation_value: Variant = studio.get("delete_confirmation")
	check(campaign_selector_value is OptionButton, "Save State Studio must create a campaign selector.")
	check(slot_list_value is ItemList, "Save State Studio must create a slot list.")
	check(overview_value is RichTextLabel, "Save State Studio must create an overview inspector.")
	check(inventory_list_value is ItemList, "Save State Studio must create an inventory inspector.")
	check(equipment_list_value is ItemList, "Save State Studio must create an equipment inspector.")
	check(loaded_ammo_list_value is ItemList, "Save State Studio must create a loaded-ammunition inspector.")
	check(supply_cycle_list_value is ItemList, "Save State Studio must create a regional supply-cycle inspector.")
	check(quest_list_value is ItemList, "Save State Studio must create a quest inspector.")
	check(state_list_value is ItemList, "Save State Studio must create a world-state inspector.")
	check(raw_text_value is TextEdit, "Save State Studio must create a raw JSON inspector.")
	check(delete_confirmation_value is ConfirmationDialog, "Save State Studio must protect destructive deletion with a confirmation dialog.")
	if campaign_selector_value is OptionButton:
		check((campaign_selector_value as OptionButton).item_count >= 1, "Save State Studio must discover the reference campaign.")
	if slot_list_value is ItemList:
		check((slot_list_value as ItemList).item_count == 4, "Reference save policy must expose autosave plus three manual slots.")
	check(str(studio.get("selected_slot_id")) == SLOT_ID, "The first occupied slot must be selected automatically.")
	if overview_value is RichTextLabel:
		check("Checksum" in (overview_value as RichTextLabel).text, "Overview must expose checksum status.")
		check("REGIONAL SUPPLY" in (overview_value as RichTextLabel).text, "Overview must expose regional supply initialisation status.")
	if inventory_list_value is ItemList:
		check((inventory_list_value as ItemList).item_count == 5, "Inventory inspector must expose all stored item stacks including ranged equipment and reserve ammunition.")
	if equipment_list_value is ItemList:
		check((equipment_list_value as ItemList).item_count == 2, "Equipment inspector must expose the stored loadout.")
	if loaded_ammo_list_value is ItemList:
		check((loaded_ammo_list_value as ItemList).item_count == 1, "Loaded-ammunition inspector must expose the stored magazine.")
	if supply_cycle_list_value is ItemList:
		check((supply_cycle_list_value as ItemList).item_count == 2, "Supply-cycle inspector must expose both saved routes.")
		check((supply_cycle_list_value as ItemList).get_item_text(0).contains("cycle"), "Supply-cycle rows must expose saved and current cycle evidence.")
	if quest_list_value is ItemList:
		check((quest_list_value as ItemList).item_count == 1, "Quest inspector must expose stored quest progress.")
	if state_list_value is ItemList:
		check((state_list_value as ItemList).item_count == 2, "World-state inspector must expose sorted durable keys.")
	if raw_text_value is TextEdit:
		check("\"checksum\"" in (raw_text_value as TextEdit).text, "Raw JSON inspector must expose the complete signed profile.")
		check("\"supply_region_cycles\"" in (raw_text_value as TextEdit).text, "Raw JSON inspector must expose durable supply cursors.")

	var sections: Dictionary = SaveStateStudio.profile_sections(profile, {}, {})
	check((sections.get("inventory", []) as Array).size() == 5, "Static profile sections must expose ranged ownership and reserve ammunition.")
	check((sections.get("equipment", []) as Array).size() == 2, "Static profile sections must expose equipment rows without editor state.")
	check((sections.get("loaded_ammo", []) as Array).size() == 1, "Static profile sections must expose loaded-magazine rows.")
	check((sections.get("quests", []) as Array).size() == 1, "Static profile sections must expose quest rows without editor state.")
	check((sections.get("state", []) as Array).size() == 2, "Static profile sections must expose world-state rows without editor state.")
	studio.call("validate_selected_profile")
	var status_value: Variant = studio.get("status_label")
	if status_value is RichTextLabel:
		check("0 error" in (status_value as RichTextLabel).text, "Selected supply-aware profile validation must pass in the editor inspector.")
	studio.call("delete_selected_profile")
	if delete_confirmation_value is ConfirmationDialog:
		check(SaveProfile.slot_label(SLOT_ID) in (delete_confirmation_value as ConfirmationDialog).dialog_text, "Deletion confirmation must identify the exact selected slot.")
	check(FileAccess.file_exists(SaveProfileStore.slot_path(CAMPAIGN_ID, SLOT_ID)), "Opening deletion confirmation must not remove the profile before approval.")

	root.remove_child(studio)
	studio.free()
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	finish()


func test_profile() -> Dictionary:
	var metadata := {
		"saved_at_unix": 500,
		"play_time_seconds": 912.0,
		"reason": "Editor inspection checkpoint",
		"map_id": "bellweather_crossing",
		"map_name": "Bellweather Crossing",
		"era_id": "verdant",
		"era_name": "Verdant Age"
	}
	var payload := {
		"map_id": "bellweather_crossing",
		"era_id": "verdant",
		"player_position": {"x": 320, "y": 224},
		"companion_position": {"x": 280, "y": 232},
		"facing": {"x": 0, "y": 1},
		"player_health": 28,
		"companion_health": 22,
		"clock_shards": 3,
		"inventory": {"museum_tonic": 1, "brass_filings": 2, "museum_flashlight": 1, "clockglass_dartcaster": 1, "archive_bolts": 7},
		"unlocked_recipes": ["ember_salve_recipe"],
		"session_state": {"bellweather:clock_shard": "collected", "studio:test": true},
		"quest_progress": {"the_missing_hour": {"status": "active", "stage_id": "trace_the_name"}},
		"equipment": {"tool": "museum_flashlight", "weapon": "clockglass_dartcaster"},
		"loaded_ammo": {"clockglass_dartcaster": 2},
		"currency_balances": {"archive_chits": 60},
		"merchant_stock": {
			"bellweather_provisions": {
				"museum_tonic": 3,
				"brass_filings": 10,
				"ember_salve": 1,
				"museum_flashlight": 1,
				"archive_bolts": 24
			},
			"underworks_exchange": {
				"ashen_resin": 4,
				"clockglass_fragment": 2,
				"salvager_wrap": 1,
				"clockglass_dartcaster": 1
			}
		},
		"economy_initialized": true,
		"supply_region_cycles": {"bellweather_route": 5, "underworks_route": 3},
		"supply_regions_initialized": true,
		"companion_command": "follow",
		"companion_hold_position": {"x": 280, "y": 232}
	}
	return SaveProfile.build_profile(CAMPAIGN_ID, SLOT_ID, metadata, payload)


func finish() -> void:
	if failures.is_empty():
		print("Save State Studio smoke test passed: campaigns, slots, summaries, equipment, supply cycles, inspectors, validation and destructive-action confirmation are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
