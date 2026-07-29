@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")
const SaveValidator = preload("res://src/content/save_validator.gd")
const EquipmentValidator = preload("res://src/content/equipment_validator.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const StoryModel = preload("res://src/game/story_model.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_campaign_id := ""
var item_definitions: Dictionary = {}
var quest_definitions: Dictionary = {}
var slot_records: Dictionary = {}
var selected_slot_id := ""
var selected_read_result: Dictionary = {}
var selected_profile: Dictionary = {}

var campaign_selector: OptionButton
var slot_list: ItemList
var overview: RichTextLabel
var inventory_list: ItemList
var equipment_list: ItemList
var quest_list: ItemList
var state_list: ItemList
var raw_text: TextEdit
var status_label: RichTextLabel
var validate_profile_button: Button
var rewrite_button: Button
var delete_button: Button
var delete_confirmation: ConfirmationDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_ui()
	refresh_campaigns()


func build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 7)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Epochbound Save & State Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_button("Refresh", refresh_slots))
	header.add_child(make_button("Validate Campaign", validate_campaign))
	validate_profile_button = make_button("Validate Profile", validate_selected_profile)
	header.add_child(validate_profile_button)
	rewrite_button = make_button("Rewrite / Migrate", rewrite_selected_profile)
	header.add_child(rewrite_button)
	delete_button = make_button("Delete", delete_selected_profile)
	header.add_child(delete_button)
	header.add_child(make_button("Open Save Folder", open_save_folder))

	var campaign_row := HBoxContainer.new()
	root.add_child(campaign_row)
	var campaign_label := Label.new()
	campaign_label.text = "CAMPAIGN"
	campaign_label.modulate = Color("e0c16c")
	campaign_row.add_child(campaign_label)
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 300
	campaign_selector.item_selected.connect(on_campaign_selected)
	campaign_row.add_child(campaign_selector)
	var hint := Label.new()
	hint.text = "Profiles live under user://save_profiles and are never written into campaign source."
	hint.modulate = Color("87949b")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_row.add_child(hint)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 5)
	split.add_child(left)
	var slots_label := Label.new()
	slots_label.text = "SAVE SLOTS"
	slots_label.modulate = Color("e0c16c")
	left.add_child(slots_label)
	slot_list = ItemList.new()
	slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_list.item_selected.connect(on_slot_selected)
	left.add_child(slot_list)
	var slot_help := RichTextLabel.new()
	slot_help.fit_content = true
	slot_help.bbcode_enabled = true
	slot_help.text = "[color=#87949b]Select a slot to inspect its checksum, inventory, quest progress and durable world keys. Rewriting upgrades a supported legacy profile and rotates the existing file into a backup.[/color]"
	left.add_child(slot_help)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(tabs)

	overview = RichTextLabel.new()
	overview.name = "Overview"
	overview.bbcode_enabled = true
	overview.scroll_active = true
	tabs.add_child(overview)

	inventory_list = ItemList.new()
	inventory_list.name = "Inventory"
	inventory_list.select_mode = ItemList.SELECT_SINGLE
	tabs.add_child(inventory_list)

	equipment_list = ItemList.new()
	equipment_list.name = "Equipment"
	equipment_list.select_mode = ItemList.SELECT_SINGLE
	tabs.add_child(equipment_list)

	quest_list = ItemList.new()
	quest_list.name = "Quests"
	quest_list.select_mode = ItemList.SELECT_SINGLE
	tabs.add_child(quest_list)

	state_list = ItemList.new()
	state_list.name = "World State"
	state_list.select_mode = ItemList.SELECT_SINGLE
	tabs.add_child(state_list)

	raw_text = TextEdit.new()
	raw_text.name = "Raw JSON"
	raw_text.editable = false
	raw_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	raw_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raw_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(raw_text)

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 58
	status_label.text = "[color=#9aa8b5]Save & State Studio ready.[/color]"
	root.add_child(status_label)
	delete_confirmation = ConfirmationDialog.new()
	delete_confirmation.title = "Delete Save Profile"
	delete_confirmation.confirmed.connect(confirm_delete_selected_profile)
	add_child(delete_confirmation)
	set_profile_actions_enabled(false)


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func refresh_campaigns(preferred_id: String = "") -> void:
	campaigns = Repository.scan_campaigns()
	campaign_selector.clear()
	var selected_index := 0
	for index in range(campaigns.size()):
		var entry: Dictionary = campaigns[index]
		campaign_selector.add_item(str(entry.get("title", entry.get("id", "Campaign"))))
		campaign_selector.set_item_metadata(index, str(entry.get("path", "")))
		if str(entry.get("id", "")) == preferred_id:
			selected_index = index
	if campaigns.is_empty():
		clear_campaign()
		set_status("No source campaigns were found under res://campaigns.", true)
		return
	campaign_selector.select(selected_index)
	on_campaign_selected(selected_index)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result: Dictionary = Repository.read_json(active_campaign_path)
	if not bool(result.get("ok", false)):
		clear_campaign()
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	active_campaign_id = str(active_campaign.get("id", ""))
	load_definitions()
	refresh_slots()
	validate_campaign()


func load_definitions() -> void:
	item_definitions = {}
	quest_definitions = {}
	if active_campaign_path.is_empty() or active_campaign.is_empty():
		return
	var item_result: Dictionary = ItemCatalog.load_item_catalogs(active_campaign_path, active_campaign)
	if bool(item_result.get("ok", false)):
		item_definitions = item_result.get("definitions", {})
	var story_result: Dictionary = StoryCatalog.load_catalogs(active_campaign_path, active_campaign)
	if bool(story_result.get("ok", false)):
		quest_definitions = story_result.get("quests", {})


func refresh_slots() -> void:
	slot_records = {}
	slot_list.clear()
	selected_slot_id = ""
	selected_read_result = {}
	selected_profile = {}
	clear_profile_views()
	set_profile_actions_enabled(false)
	if active_campaign.is_empty() or active_campaign_id.is_empty():
		return
	var first_existing_index := -1
	var slots := SaveProfile.all_slot_ids(active_campaign)
	for slot_id_value in slots:
		var slot_id := str(slot_id_value)
		var result: Dictionary = SaveProfileStore.read_profile(active_campaign_id, slot_id)
		var label := "%s   EMPTY" % SaveProfile.slot_label(slot_id)
		if bool(result.get("ok", false)):
			var profile: Dictionary = result.get("profile", {})
			var summary := SaveProfile.profile_summary(profile)
			label = "%s   %s / %s   %s" % [
				SaveProfile.slot_label(slot_id),
				str(summary.get("map_id", "")).replace("_", " ").capitalize(),
				str(summary.get("era_id", "")).replace("_", " ").capitalize(),
				format_play_time(float(summary.get("play_time_seconds", 0.0)))
			]
			slot_records[slot_id] = result
			if first_existing_index < 0:
				first_existing_index = slot_list.item_count
		var item_index := slot_list.item_count
		slot_list.add_item(label)
		slot_list.set_item_metadata(item_index, slot_id)
	if first_existing_index >= 0:
		slot_list.select(first_existing_index)
		on_slot_selected(first_existing_index)
	else:
		set_status("No save profiles exist yet for '%s'. Run the campaign and use K / L3 to create one." % active_campaign.get("title", active_campaign_id), false)


func on_slot_selected(index: int) -> void:
	if index < 0 or index >= slot_list.item_count:
		return
	selected_slot_id = str(slot_list.get_item_metadata(index))
	selected_read_result = slot_records.get(selected_slot_id, {})
	if selected_read_result.is_empty() or not bool(selected_read_result.get("ok", false)):
		selected_profile = {}
		clear_profile_views()
		set_profile_actions_enabled(false)
		set_status("%s is empty." % SaveProfile.slot_label(selected_slot_id), false)
		return
	selected_profile = selected_read_result.get("profile", {})
	display_profile(selected_profile)
	set_profile_actions_enabled(true)
	var migrated := bool(selected_read_result.get("migrated", false))
	var recovered := bool(selected_read_result.get("recovered_from_backup", false))
	var suffix := ""
	if migrated:
		suffix += " Legacy schema was migrated in memory."
	if recovered:
		suffix += " The backup copy was used."
	set_status("Loaded %s.%s" % [SaveProfile.slot_label(selected_slot_id), suffix], false)


func display_profile(profile: Dictionary) -> void:
	var sections := profile_sections(profile, item_definitions, quest_definitions)
	var summary: Dictionary = sections.get("summary", {})
	var metadata: Dictionary = profile.get("metadata", {})
	var integrity := "VALID" if SaveProfile.checksum_valid(profile) else "INVALID"
	overview.text = (
		"[font_size=22][color=#f0dfad]%s[/color][/font_size]\n\n" % SaveProfile.slot_label(str(profile.get("slot_id", "")))
		+ "[color=#e7c66b]Campaign[/color]  %s\n" % str(profile.get("campaign_id", ""))
		+ "[color=#e7c66b]Schema[/color]  %d\n" % int(profile.get("schema_version", -1))
		+ "[color=#e7c66b]Checksum[/color]  %s\n" % integrity
		+ "[color=#e7c66b]Saved[/color]  %s\n" % format_timestamp(int(summary.get("saved_at_unix", 0)))
		+ "[color=#e7c66b]Reason[/color]  %s\n\n" % str(summary.get("reason", ""))
		+ "[color=#8fa9a5]LOCATION[/color]\n%s / %s\n" % [str(summary.get("map_id", "")).replace("_", " ").capitalize(), str(summary.get("era_id", "")).replace("_", " ").capitalize()]
		+ "Play time  %s\n\n" % format_play_time(float(summary.get("play_time_seconds", 0.0)))
		+ "[color=#8fa9a5]ACTORS[/color]\nPlayer health  %d\nCompanion health  %d\nClock shards  %d\n\n" % [int(summary.get("player_health", 0)), int(summary.get("companion_health", 0)), int(summary.get("clock_shards", 0))]
		+ "[color=#8fa9a5]DURABLE STATE[/color]\nInventory stacks  %d\nEquipped slots  %d\nActive quests  %d\nCompleted quests  %d\nState keys  %d\n\n" % [int(summary.get("inventory_stacks", 0)), int(summary.get("equipment_slots", 0)), int(summary.get("active_quests", 0)), int(summary.get("completed_quests", 0)), int(summary.get("state_keys", 0))]
		+ "[color=#87949b]Profile ID: %s\nChecksum: %s\nMap label: %s\nEra label: %s[/color]" % [str(profile.get("profile_id", "")), str(profile.get("checksum", "")), str(metadata.get("map_name", "")), str(metadata.get("era_name", ""))]
	)
	inventory_list.clear()
	for row_value in sections.get("inventory", []):
		inventory_list.add_item(str(row_value))
	if inventory_list.item_count == 0:
		inventory_list.add_item("Inventory is empty.")
	equipment_list.clear()
	for row_value in sections.get("equipment", []):
		equipment_list.add_item(str(row_value))
	if equipment_list.item_count == 0:
		equipment_list.add_item("No equipment is stored.")
	quest_list.clear()
	for row_value in sections.get("quests", []):
		quest_list.add_item(str(row_value))
	if quest_list.item_count == 0:
		quest_list.add_item("No quest progress is stored.")
	state_list.clear()
	for row_value in sections.get("state", []):
		state_list.add_item(str(row_value))
	if state_list.item_count == 0:
		state_list.add_item("No durable world keys are stored.")
	raw_text.text = JSON.stringify(SaveProfile.canonicalize(profile), "\t", true)


static func profile_sections(
	profile: Dictionary,
	items: Dictionary = {},
	quests: Dictionary = {}
) -> Dictionary:
	var summary := SaveProfile.profile_summary(profile)
	var payload_value: Variant = profile.get("payload", {})
	var payload: Dictionary = payload_value if typeof(payload_value) == TYPE_DICTIONARY else {}
	var inventory_rows: Array[String] = []
	var inventory_value: Variant = payload.get("inventory", {})
	if typeof(inventory_value) == TYPE_DICTIONARY:
		var inventory: Dictionary = inventory_value
		var item_ids: Array[String] = []
		for item_key in inventory.keys():
			item_ids.append(str(item_key))
		item_ids.sort()
		for item_id in item_ids:
			var definition_data := ItemCatalog.item(items, item_id)
			var name := ItemCatalog.item_name(definition_data, item_id)
			inventory_rows.append("%s   x%d   [%s]" % [name, int(inventory.get(item_id, 0)), item_id])
	var equipment_rows: Array[String] = []
	var equipment_value: Variant = payload.get("equipment", {})
	if typeof(equipment_value) == TYPE_DICTIONARY:
		var equipment: Dictionary = equipment_value
		var slot_ids: Array[String] = []
		for slot_key in equipment.keys():
			slot_ids.append(str(slot_key))
		slot_ids.sort()
		for slot_id in slot_ids:
			var item_id := str(equipment.get(slot_id, ""))
			var definition_data := ItemCatalog.item(items, item_id)
			var item_name := ItemCatalog.item_name(definition_data, item_id)
			equipment_rows.append("%s   %s   [%s]" % [slot_id.replace("_", " ").capitalize(), item_name, item_id])
	var quest_rows: Array[String] = []
	var progress_value: Variant = payload.get("quest_progress", {})
	if typeof(progress_value) == TYPE_DICTIONARY:
		var progress: Dictionary = progress_value
		var quest_ids: Array[String] = []
		for quest_key in progress.keys():
			quest_ids.append(str(quest_key))
		quest_ids.sort()
		for quest_id in quest_ids:
			var record_value: Variant = progress.get(quest_id, {})
			var record: Dictionary = record_value if typeof(record_value) == TYPE_DICTIONARY else {}
			var title := StoryModel.quest_title(quests, quest_id)
			quest_rows.append("%s   %s   stage: %s   [%s]" % [title, str(record.get("status", "not_started")).to_upper(), str(record.get("stage_id", "")), quest_id])
	var state_rows: Array[String] = []
	var state_value: Variant = payload.get("session_state", {})
	if typeof(state_value) == TYPE_DICTIONARY:
		var state: Dictionary = state_value
		var keys: Array[String] = []
		for key_value in state.keys():
			keys.append(str(key_value))
		keys.sort()
		for key in keys:
			state_rows.append("%s = %s" % [key, format_state_value(state.get(key))])
	return {"summary": summary, "inventory": inventory_rows, "equipment": equipment_rows, "quests": quest_rows, "state": state_rows}


static func format_state_value(value: Variant) -> String:
	if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY]:
		return JSON.stringify(value, "", true)
	return str(value)


func validate_campaign() -> void:
	if active_campaign_path.is_empty():
		return
	var report: Dictionary = EquipmentValidator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func validate_selected_profile() -> void:
	if selected_profile.is_empty() or active_campaign_path.is_empty():
		return
	var report: Dictionary = EquipmentValidator.validate_profile(selected_profile, active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func rewrite_selected_profile() -> void:
	if selected_read_result.is_empty():
		return
	var validation: Dictionary = EquipmentValidator.validate_profile(selected_profile, active_campaign_path)
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


func delete_selected_profile() -> void:
	if selected_slot_id.is_empty() or active_campaign_id.is_empty() or selected_profile.is_empty():
		return
	delete_confirmation.dialog_text = "Delete %s and its backup copy? This cannot be undone from the editor." % SaveProfile.slot_label(selected_slot_id)
	delete_confirmation.popup_centered(Vector2i(500, 170))


func confirm_delete_selected_profile() -> void:
	if selected_slot_id.is_empty() or active_campaign_id.is_empty() or selected_profile.is_empty():
		return
	var deleted_slot := selected_slot_id
	var result: Dictionary = SaveProfileStore.delete_profile(active_campaign_id, deleted_slot)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return
	refresh_slots()
	set_status("Deleted %s and its backup copy." % SaveProfile.slot_label(deleted_slot), false)


func select_slot_id(slot_id: String) -> void:
	for index in range(slot_list.item_count):
		if str(slot_list.get_item_metadata(index)) == slot_id:
			slot_list.select(index)
			on_slot_selected(index)
			return


func open_save_folder() -> void:
	if active_campaign_id.is_empty():
		return
	var path := SaveProfileStore.campaign_directory(active_campaign_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	OS.shell_open(ProjectSettings.globalize_path(path))


func set_profile_actions_enabled(enabled: bool) -> void:
	validate_profile_button.disabled = not enabled
	rewrite_button.disabled = not enabled
	delete_button.disabled = not enabled


func clear_campaign() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_campaign_id = ""
	item_definitions = {}
	quest_definitions = {}
	slot_records = {}
	slot_list.clear()
	clear_profile_views()
	set_profile_actions_enabled(false)


func clear_profile_views() -> void:
	overview.text = "[color=#87949b]Select an occupied save slot to inspect its deterministic state.[/color]"
	inventory_list.clear()
	equipment_list.clear()
	quest_list.clear()
	state_list.clear()
	raw_text.text = ""


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	var errors_value: Variant = report.get("errors", [])
	var warnings_value: Variant = report.get("warnings", [])
	var error_count: int = errors_value.size() if typeof(errors_value) == TYPE_ARRAY else 0
	var warning_count: int = warnings_value.size() if typeof(warnings_value) == TYPE_ARRAY else 0
	lines.append("Validation completed with %d warning(s) and %d error(s)." % [warning_count, error_count])
	if typeof(warnings_value) == TYPE_ARRAY:
		for warning in warnings_value:
			lines.append("WARNING: %s" % warning)
	if typeof(errors_value) == TYPE_ARRAY:
		for error in errors_value:
			lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func format_messages(messages: Variant) -> String:
	var lines := PackedStringArray()
	if typeof(messages) == TYPE_ARRAY:
		for message in messages:
			lines.append(str(message))
	return "\n".join(lines)


func format_play_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]


func format_timestamp(unix_time: int) -> String:
	if unix_time <= 0:
		return "Unknown"
	var data: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d:%02d UTC" % [int(data.get("year", 0)), int(data.get("month", 0)), int(data.get("day", 0)), int(data.get("hour", 0)), int(data.get("minute", 0)), int(data.get("second", 0))]


func set_status(message: String, is_error: bool) -> void:
	var color := "#ff9797" if is_error else "#acd8b2"
	status_label.text = "[color=%s]%s[/color]" % [color, message]
