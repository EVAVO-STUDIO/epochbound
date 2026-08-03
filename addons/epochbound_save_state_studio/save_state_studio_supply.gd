@tool
extends "res://addons/epochbound_save_state_studio/save_state_studio.gd"

const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyModel = preload("res://src/game/supply_region_model.gd")
const SupplyCompleteValidator = preload("res://src/content/complete_content_validator.gd")

var supply_region_definitions: Dictionary = {}
var supply_cycle_list: ItemList


func build_ui() -> void:
	super.build_ui()
	var tabs := profile_tab_container()
	if tabs != null:
		supply_cycle_list = ItemList.new()
		supply_cycle_list.name = "Supply Cycles"
		supply_cycle_list.select_mode = ItemList.SELECT_SINGLE
		tabs.add_child(supply_cycle_list)


func profile_tab_container() -> TabContainer:
	for child in get_children():
		for grandchild in child.get_children():
			if grandchild is HSplitContainer:
				for split_child in grandchild.get_children():
					if split_child is TabContainer:
						return split_child as TabContainer
	return null


func load_definitions() -> void:
	super.load_definitions()
	supply_region_definitions = {}
	if active_campaign_path.is_empty() or active_campaign.is_empty():
		return
	var result := SupplyCatalog.load_catalogs(active_campaign_path, active_campaign)
	if bool(result.get("ok", false)):
		supply_region_definitions = result.get("definitions", {})


func display_profile(profile: Dictionary) -> void:
	super.display_profile(profile)
	if supply_cycle_list == null:
		return
	supply_cycle_list.clear()
	var metadata_value: Variant = profile.get("metadata", {})
	var metadata: Dictionary = metadata_value if typeof(metadata_value) == TYPE_DICTIONARY else {}
	var play_time := maxf(0.0, float(metadata.get("play_time_seconds", 0.0)))
	var payload_value: Variant = profile.get("payload", {})
	var payload: Dictionary = payload_value if typeof(payload_value) == TYPE_DICTIONARY else {}
	var cycles_value: Variant = payload.get("supply_region_cycles", {})
	var cycles: Dictionary = cycles_value if typeof(cycles_value) == TYPE_DICTIONARY else {}
	var ids: Array[String] = []
	for region_id_value in supply_region_definitions.keys():
		ids.append(str(region_id_value))
	ids.sort()
	for region_id in ids:
		var region_data := SupplyCatalog.region(supply_region_definitions, region_id)
		var current_cycle := SupplyModel.cycle_at(region_data, play_time)
		var saved_cycle := int(cycles.get(region_id, current_cycle))
		var next_supply := SupplyCatalog.format_duration(SupplyModel.seconds_until_next_cycle(region_data, play_time))
		supply_cycle_list.add_item(
			"%s   cycle %d / %d   next %s   [%s]" % [
				SupplyCatalog.region_name(supply_region_definitions, region_id),
				saved_cycle,
				current_cycle,
				next_supply,
				region_id
			]
		)
	if supply_cycle_list.item_count == 0:
		supply_cycle_list.add_item("No regional supply cycles are stored.")
	var initialised := bool(payload.get("supply_regions_initialized", false))
	overview.text += "\n\n[color=#8fa9a5]REGIONAL SUPPLY[/color]\nRoutes  %d\nInitialised  %s" % [
		supply_region_definitions.size(),
		"YES" if initialised else "NO — current play-time cycles will initialise on load"
	]


func clear_profile_views() -> void:
	super.clear_profile_views()
	if supply_cycle_list != null:
		supply_cycle_list.clear()


func validate_campaign() -> void:
	if active_campaign_path.is_empty():
		return
	var report := SupplyCompleteValidator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func validate_selected_profile() -> void:
	if selected_profile.is_empty() or active_campaign_path.is_empty():
		return
	var report := SupplyCompleteValidator.validate_profile(selected_profile, active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func rewrite_selected_profile() -> void:
	if selected_read_result.is_empty():
		return
	var validation := SupplyCompleteValidator.validate_profile(selected_profile, active_campaign_path)
	if not bool(validation.get("ok", false)):
		set_status("Cannot rewrite an invalid profile. %s" % format_messages(validation.get("errors", [])), true)
		return
	var result: Dictionary = SaveProfileStore.rewrite_migrated_profile(selected_read_result)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return
	var previous_slot := selected_slot_id
	refresh_slots()
	select_slot_id(previous_slot)
	set_status("Rewrote %s using schema %d and rotated the previous file into a backup." % [SaveProfile.slot_label(previous_slot), SaveProfile.CURRENT_SCHEMA], false)
