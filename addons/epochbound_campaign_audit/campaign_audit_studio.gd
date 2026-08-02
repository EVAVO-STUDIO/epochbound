@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const CampaignAudit = preload("res://src/content/campaign_audit.gd")

var campaign_selector: OptionButton
var summary_label: Label
var metrics_label: Label
var findings_tree: Tree
var export_button: Button
var campaigns: Array[Dictionary] = []
var current_campaign_path := ""
var last_report: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_ui()
	refresh_campaigns()


func build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 8)
	add_child(root_box)

	var header := HBoxContainer.new()
	root_box.add_child(header)
	var title := Label.new()
	title.text = "CAMPAIGN AUDIT STUDIO"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 260
	campaign_selector.item_selected.connect(Callable(self, "_on_campaign_selected"))
	header.add_child(campaign_selector)
	var run_button := Button.new()
	run_button.text = "Run Audit"
	run_button.pressed.connect(Callable(self, "run_selected_audit"))
	header.add_child(run_button)
	export_button = Button.new()
	export_button.text = "Export JSON"
	export_button.disabled = true
	export_button.pressed.connect(Callable(self, "export_last_report"))
	header.add_child(export_button)
	var folder_button := Button.new()
	folder_button.text = "Open Reports"
	folder_button.pressed.connect(Callable(self, "open_report_folder"))
	header.add_child(folder_button)

	summary_label = Label.new()
	summary_label.text = "Select a campaign and run the deterministic production audit."
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(summary_label)
	metrics_label = Label.new()
	metrics_label.text = ""
	metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(metrics_label)

	findings_tree = Tree.new()
	findings_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	findings_tree.columns = 4
	findings_tree.column_titles_visible = true
	findings_tree.hide_root = true
	findings_tree.set_column_title(0, "Severity")
	findings_tree.set_column_title(1, "Code")
	findings_tree.set_column_title(2, "Context")
	findings_tree.set_column_title(3, "Finding")
	findings_tree.set_column_custom_minimum_width(0, 90)
	findings_tree.set_column_custom_minimum_width(1, 230)
	findings_tree.set_column_custom_minimum_width(2, 170)
	findings_tree.set_column_expand(3, true)
	root_box.add_child(findings_tree)


func refresh_campaigns() -> void:
	campaigns.clear()
	campaign_selector.clear()
	for value in Repository.scan_playable_campaigns():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		campaigns.append(entry)
		campaign_selector.add_item("%s  [%s]" % [str(entry.get("title", entry.get("id", "Campaign"))), str(entry.get("source", "built_in")).to_upper()])
	if campaigns.is_empty():
		current_campaign_path = ""
		summary_label.text = "No campaigns were discovered."
		return
	campaign_selector.select(0)
	_on_campaign_selected(0)


func _on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaigns.size():
		current_campaign_path = ""
		return
	current_campaign_path = str(campaigns[index].get("path", ""))
	summary_label.text = "Ready to audit %s." % str(campaigns[index].get("title", campaigns[index].get("id", "Campaign")))
	metrics_label.text = ""
	last_report.clear()
	export_button.disabled = true
	findings_tree.clear()


func run_selected_audit() -> void:
	if current_campaign_path.is_empty():
		summary_label.text = "Select a campaign first."
		return
	run_audit_for_path(current_campaign_path)


func run_audit_for_path(campaign_path: String) -> Dictionary:
	current_campaign_path = campaign_path
	last_report = CampaignAudit.audit_campaign_path(campaign_path)
	if is_instance_valid(findings_tree):
		render_report(last_report)
	return last_report


func render_report(report: Dictionary) -> void:
	findings_tree.clear()
	var root: TreeItem = findings_tree.create_item()
	var blockers := int(report.get("blocker_count", 0))
	var warnings := int(report.get("warning_count", 0))
	summary_label.text = "%s — %d blocker(s), %d warning(s)" % [str(report.get("campaign_id", "Campaign")), blockers, warnings]
	var metrics: Dictionary = report.get("metrics", {})
	metrics_label.text = (
		"Maps %d/%d reachable   •   Capabilities %d   •   Quests %d   •   Restorative sources %d   •   Probes %d\n" % [
			int(metrics.get("reachable_map_count", 0)),
			int(metrics.get("map_count", 0)),
			int(metrics.get("required_capability_count", 0)),
			int(metrics.get("quest_count", 0)),
			int(metrics.get("restorative_source_count", 0)),
			int(report.get("probe_count", 0))
		]
		+ "Progression items %d   •   Progression capabilities %d   •   Source risks %d   •   Merchant-only %d   •   Affordability risks %d" % [
			int(metrics.get("progression_item_count", 0)),
			int(metrics.get("progression_capability_count", 0)),
			int(metrics.get("progression_source_risk_count", 0)),
			int(metrics.get("merchant_only_progression_count", 0)),
			int(metrics.get("affordability_risk_count", 0))
		]
	)
	for finding_value in report.get("findings", []):
		if typeof(finding_value) != TYPE_DICTIONARY:
			continue
		var finding: Dictionary = finding_value
		var item: TreeItem = findings_tree.create_item(root)
		var severity := str(finding.get("severity", "info"))
		item.set_text(0, severity.to_upper())
		item.set_text(1, str(finding.get("code", "")))
		item.set_text(2, str(finding.get("context", "")))
		item.set_text(3, str(finding.get("message", "")))
		var color: Color = Color("d98b7b") if severity == "blocker" else Color("e4c06a") if severity == "warning" else Color("86b9a4")
		item.set_custom_color(0, color)
	export_button.disabled = false


func export_last_report() -> void:
	if last_report.is_empty():
		return
	var campaign_id := str(last_report.get("campaign_id", "campaign"))
	var destination := "user://audit_reports/%s-audit.json" % campaign_id
	var result: Dictionary = export_last_report_to(destination)
	if bool(result.get("ok", false)):
		summary_label.text = "Audit exported to %s" % destination
	else:
		summary_label.text = "Audit export failed: %s" % join_messages(result.get("errors", []))


func export_last_report_to(path: String) -> Dictionary:
	if last_report.is_empty():
		return {"ok": false, "errors": ["No audit report is available."]}
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "errors": ["Could not create the audit report directory."]}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["Could not write %s." % path]}
	file.store_string(JSON.stringify(last_report, "\t", true) + "\n")
	file.flush()
	return {"ok": true, "path": path, "errors": []}


func join_messages(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return str(value)
	var output := PackedStringArray()
	for message_value in value:
		output.append(str(message_value))
	return "; ".join(output)


func open_report_folder() -> void:
	var path := "user://audit_reports"
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(ProjectSettings.globalize_path(path))
