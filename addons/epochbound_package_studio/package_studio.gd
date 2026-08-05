@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")
const Validator = preload("res://src/content/package_release_validator.gd")

var campaigns: Array = []
var active_campaign_path := ""
var active_campaign: Dictionary = {}

var campaign_selector: OptionButton
var version_edit: LineEdit
var channel_selector: OptionButton
var package_name_edit: LineEdit
var runtime_edit: LineEdit
var license_edit: LineEdit
var package_list: ItemList
var import_path_edit: LineEdit
var replace_check: CheckBox
var status_label: RichTextLabel
var import_dialog: FileDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_ui()
	refresh_campaigns()
	refresh_packages()


func build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Epochbound Package & Release Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Exports", open_exports_folder))
	header.add_child(make_button("Open Installed", open_installed_folder))

	var selection := HBoxContainer.new()
	root.add_child(selection)
	selection.add_child(make_label("CAMPAIGN"))
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 260
	campaign_selector.item_selected.connect(on_campaign_selected)
	selection.add_child(campaign_selector)
	selection.add_child(make_button("Refresh", refresh_campaigns))

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var release_panel := VBoxContainer.new()
	release_panel.custom_minimum_size.x = 320
	split.add_child(release_panel)
	release_panel.add_child(make_heading("RELEASE METADATA"))
	version_edit = add_line_field(release_panel, "Semantic version")
	channel_selector = OptionButton.new()
	for channel in ["development", "alpha", "beta", "release"]:
		var index := channel_selector.item_count
		channel_selector.add_item(channel.capitalize())
		channel_selector.set_item_metadata(index, channel)
	release_panel.add_child(make_labeled("Channel", channel_selector))
	package_name_edit = add_line_field(release_panel, "Package name")
	runtime_edit = add_line_field(release_panel, "Minimum runtime")
	license_edit = add_line_field(release_panel, "Licence")
	release_panel.add_child(make_button("Save Metadata", save_release_metadata))
	release_panel.add_child(make_button("Export Package", export_active_campaign))
	var policy := RichTextLabel.new()
	policy.fit_content = true
	policy.bbcode_enabled = true
	policy.text = "[color=#9aa8b5]Exports are data-only, path-safe, size-limited and SHA-256 verified. Identical source content produces identical package bytes.[/color]"
	release_panel.add_child(policy)

	var package_panel := VBoxContainer.new()
	package_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(package_panel)
	package_panel.add_child(make_heading("EXPORTED PACKAGES"))
	package_list = ItemList.new()
	package_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	package_list.item_selected.connect(on_package_selected)
	package_panel.add_child(package_list)
	package_panel.add_child(make_button("Refresh Packages", refresh_packages))
	package_panel.add_child(make_heading("INSPECT OR INSTALL"))
	var path_row := HBoxContainer.new()
	package_panel.add_child(path_row)
	import_path_edit = LineEdit.new()
	import_path_edit.placeholder_text = "Path to .epochbound.zip"
	import_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(import_path_edit)
	path_row.add_child(make_button("Browse", browse_package))
	replace_check = CheckBox.new()
	replace_check.text = "Replace an existing custom campaign after validation"
	package_panel.add_child(replace_check)
	var actions := HBoxContainer.new()
	package_panel.add_child(actions)
	actions.add_child(make_button("Inspect Package", inspect_selected_package))
	actions.add_child(make_button("Install Package", install_selected_package))

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 82
	status_label.text = "[color=#9aa8b5]Package Studio ready.[/color]"
	root.add_child(status_label)

	# FileDialog remains available in the editor and can also be instantiated by
	# the headless editor-state regression. EditorFileDialog is editor-only and
	# emitted a runtime error before the smoke test could inspect the UI.
	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.add_filter("*.zip", "Epochbound campaign package")
	import_dialog.file_selected.connect(on_import_file_selected)
	add_child(import_dialog)


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color("aeb8c2")
	return label


func make_heading(text: String) -> Label:
	var label := make_label(text)
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color("e0c16c")
	return label


func make_labeled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(make_label(text))
	box.add_child(control)
	return box


func add_line_field(parent: Container, label_text: String) -> LineEdit:
	var edit := LineEdit.new()
	parent.add_child(make_labeled(label_text, edit))
	return edit


func refresh_campaigns(preferred_id: String = "") -> void:
	campaigns = Repository.scan_campaigns()
	campaign_selector.clear()
	var selected := 0
	for index in range(campaigns.size()):
		var entry: Dictionary = campaigns[index]
		campaign_selector.add_item(str(entry.get("title", entry.get("id", "Campaign"))))
		campaign_selector.set_item_metadata(index, str(entry.get("path", "")))
		if str(entry.get("id", "")) == preferred_id:
			selected = index
	if campaigns.is_empty():
		active_campaign_path = ""
		active_campaign = {}
		set_status("No source campaigns were found.", true)
		return
	campaign_selector.select(selected)
	on_campaign_selected(selected)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	populate_release_fields()


func populate_release_fields() -> void:
	var release: Dictionary = CampaignPackage.release_record(active_campaign)
	version_edit.text = str(release.get("version", "0.1.0"))
	package_name_edit.text = str(release.get("package_name", active_campaign.get("id", "campaign")))
	runtime_edit.text = str(release.get("minimum_runtime", "0.1.0"))
	license_edit.text = str(release.get("license", "All Rights Reserved"))
	var desired := str(release.get("channel", "development"))
	for index in range(channel_selector.item_count):
		if str(channel_selector.get_item_metadata(index)) == desired:
			channel_selector.select(index)
			break


func authored_release() -> Dictionary:
	return {
		"version": version_edit.text.strip_edges(),
		"channel": str(channel_selector.get_item_metadata(channel_selector.selected)),
		"package_name": Repository.normalise_id(package_name_edit.text),
		"minimum_runtime": runtime_edit.text.strip_edges(),
		"license": license_edit.text.strip_edges()
	}


func save_release_metadata() -> bool:
	if active_campaign_path.is_empty() or active_campaign.is_empty():
		return false
	var previous := active_campaign.duplicate(true)
	active_campaign["release"] = authored_release()
	var save_result := Repository.save_json(active_campaign_path, active_campaign)
	if not bool(save_result.get("ok", false)):
		active_campaign = previous
		set_status(format_messages(save_result.get("errors", [])), true)
		return false
	var report := Validator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		Repository.save_json(active_campaign_path, previous)
		active_campaign = previous
		populate_release_fields()
		set_status(format_report(report), true)
		return false
	EditorInterface.get_resource_filesystem().scan()
	set_status(format_report(report), false)
	return true


func export_active_campaign() -> void:
	if not save_release_metadata():
		return
	var result := CampaignPackage.export_campaign(active_campaign_path)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return
	refresh_packages()
	import_path_edit.text = ProjectSettings.globalize_path(str(result.get("path", "")))
	set_status("Exported %d files.\nSHA-256: %s" % [result.get("file_count", 0), result.get("sha256", "")], false)


func refresh_packages() -> void:
	package_list.clear()
	DirAccess.make_dir_recursive_absolute(CampaignPackage.EXPORT_ROOT)
	var directory := DirAccess.open(CampaignPackage.EXPORT_ROOT)
	if directory == null:
		return
	var names := PackedStringArray()
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.to_lower().ends_with(".zip"):
			names.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	names.sort()
	for name in names:
		var index := package_list.item_count
		package_list.add_item(name)
		package_list.set_item_metadata(index, CampaignPackage.EXPORT_ROOT.path_join(name))


func on_package_selected(index: int) -> void:
	if index >= 0 and index < package_list.item_count:
		import_path_edit.text = ProjectSettings.globalize_path(str(package_list.get_item_metadata(index)))


func browse_package() -> void:
	import_dialog.popup_centered_ratio(0.72)


func on_import_file_selected(path: String) -> void:
	import_path_edit.text = path


func resolved_import_path() -> String:
	return import_path_edit.text.strip_edges()


func inspect_selected_package() -> void:
	var result := CampaignPackage.inspect_package(resolved_import_path())
	set_status(format_package_report(result), not bool(result.get("ok", false)))


func install_selected_package() -> void:
	var result := CampaignPackage.install_package(resolved_import_path(), replace_check.button_pressed)
	if bool(result.get("ok", false)):
		EditorInterface.get_resource_filesystem().scan()
	set_status(format_install_report(result), not bool(result.get("ok", false)))


func validate_all_campaigns() -> void:
	var report := Validator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray(["%d release record(s), %d warning(s), %d error(s)." % [report.get("release_count", 0), report.get("warnings", []).size(), report.get("errors", []).size()]])
	for warning in report.get("warnings", []):
		lines.append("WARNING: %s" % warning)
	for error in report.get("errors", []):
		lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func format_package_report(report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		return format_messages(report.get("errors", []))
	var manifest: Dictionary = report.get("manifest", {})
	var release: Dictionary = manifest.get("release", {})
	return "%s %s\n%d file(s), %d expanded byte(s)\nSHA-256: %s" % [manifest.get("title", manifest.get("campaign_id", "Campaign")), release.get("version", "0.0.0"), report.get("file_count", 0), report.get("total_bytes", 0), report.get("sha256", "")]


func format_install_report(report: Dictionary) -> String:
	return "Installed '%s' to %s." % [report.get("campaign_id", "campaign"), report.get("target", Repository.USER_ROOT)] if bool(report.get("ok", false)) else format_messages(report.get("errors", []))


func format_messages(messages: Variant) -> String:
	if typeof(messages) != TYPE_ARRAY:
		return str(messages)
	var lines := PackedStringArray()
	for message in messages:
		lines.append(str(message))
	return "\n".join(lines)


func set_status(message: String, is_error: bool) -> void:
	status_label.text = "[color=%s]%s[/color]" % ["#ff9797" if is_error else "#acd8b2", message]


func open_exports_folder() -> void:
	DirAccess.make_dir_recursive_absolute(CampaignPackage.EXPORT_ROOT)
	OS.shell_open(ProjectSettings.globalize_path(CampaignPackage.EXPORT_ROOT))


func open_installed_folder() -> void:
	DirAccess.make_dir_recursive_absolute(Repository.USER_ROOT)
	OS.shell_open(ProjectSettings.globalize_path(Repository.USER_ROOT))
