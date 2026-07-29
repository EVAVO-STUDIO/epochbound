@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const StoryValidator = preload("res://src/content/story_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_story_catalog: Dictionary = {}
var active_story_path := ""
var conversation_definitions: Dictionary = {}
var quest_definitions: Dictionary = {}
var selected_conversation_id := ""
var selected_node_id := ""
var selected_quest_id := ""
var selected_stage_id := ""

var campaign_selector: OptionButton
var tabs: TabContainer
var status_label: RichTextLabel

var conversation_list: ItemList
var new_conversation_id: LineEdit
var node_list: ItemList
var new_node_id: LineEdit
var graph: GraphEdit
var conversation_name_edit: LineEdit
var conversation_start_selector: OptionButton
var conversation_conditions_edit: TextEdit
var node_id_edit: LineEdit
var node_kind_label: Label
var node_speaker_edit: LineEdit
var node_text_edit: TextEdit
var node_next_selector: OptionButton
var node_prompt_edit: TextEdit
var node_choices_edit: TextEdit
var node_conditions_edit: TextEdit
var node_effects_edit: TextEdit
var apply_conversation_button: Button
var delete_conversation_button: Button
var apply_node_button: Button
var delete_node_button: Button

var quest_list: ItemList
var new_quest_id: LineEdit
var stage_list: ItemList
var new_stage_id: LineEdit
var quest_title_edit: LineEdit
var quest_summary_edit: TextEdit
var quest_auto_start: CheckBox
var quest_initial_stage_selector: OptionButton
var quest_rewards_edit: TextEdit
var stage_id_edit: LineEdit
var stage_description_edit: TextEdit
var stage_next_selector: OptionButton
var stage_conditions_edit: TextEdit
var apply_quest_button: Button
var delete_quest_button: Button
var apply_stage_button: Button
var delete_stage_button: Button


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
	title.text = "Epochbound Story Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_button("Validate All", validate_all))
	header.add_child(make_button("Open Story Folder", open_story_folder))

	var selector_row := HBoxContainer.new()
	root.add_child(selector_row)
	selector_row.add_child(make_heading("CAMPAIGN"))
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 300
	campaign_selector.item_selected.connect(on_campaign_selected)
	selector_row.add_child(campaign_selector)
	var selector_spacer := Control.new()
	selector_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector_row.add_child(selector_spacer)
	var help := Label.new()
	help.text = "Graph preview + source-controlled typed records"
	help.modulate = Color("85939b")
	selector_row.add_child(help)

	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	build_conversation_tab()
	build_quest_tab()

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 64
	status_label.text = "[color=#9aa8b5]Story Studio ready.[/color]"
	root.add_child(status_label)


func build_conversation_tab() -> void:
	var tab := HSplitContainer.new()
	tab.name = "Conversations"
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("CONVERSATIONS"))
	conversation_list = ItemList.new()
	conversation_list.custom_minimum_size.y = 160
	conversation_list.item_selected.connect(on_conversation_selected)
	left.add_child(conversation_list)
	new_conversation_id = LineEdit.new()
	new_conversation_id.placeholder_text = "new_conversation_id"
	left.add_child(new_conversation_id)
	var conversation_buttons := HBoxContainer.new()
	conversation_buttons.add_child(make_button("Add", add_conversation))
	delete_conversation_button = make_button("Delete", delete_conversation)
	conversation_buttons.add_child(delete_conversation_button)
	left.add_child(conversation_buttons)
	left.add_child(HSeparator.new())
	left.add_child(make_heading("NODES"))
	node_list = ItemList.new()
	node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_list.item_selected.connect(on_node_selected)
	left.add_child(node_list)
	new_node_id = LineEdit.new()
	new_node_id.placeholder_text = "new_node_id"
	left.add_child(new_node_id)
	var node_buttons_one := HBoxContainer.new()
	node_buttons_one.add_child(make_button("Line", func() -> void: add_node("line")))
	node_buttons_one.add_child(make_button("Choice", func() -> void: add_node("choice")))
	node_buttons_one.add_child(make_button("End", func() -> void: add_node("end")))
	left.add_child(node_buttons_one)
	delete_node_button = make_button("Delete Selected Node", delete_node)
	left.add_child(delete_node_button)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 2.4
	tab.add_child(center)
	var graph_help := Label.new()
	graph_help.text = "Drag nodes to organise the authored graph. Connections are generated from next-node records."
	graph_help.modulate = Color("84929a")
	center.add_child(graph_help)
	graph = GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(560, 480)
	graph.minimap_enabled = true
	graph.show_grid = true
	graph.node_selected.connect(on_graph_node_selected)
	center.add_child(graph)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 360
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	right_scroll.add_child(right)
	right.add_child(make_heading("CONVERSATION"))
	right.add_child(make_field_label("Display name"))
	conversation_name_edit = LineEdit.new()
	right.add_child(conversation_name_edit)
	right.add_child(make_field_label("Start node"))
	conversation_start_selector = OptionButton.new()
	right.add_child(conversation_start_selector)
	right.add_child(make_field_label("Availability conditions · one JSON object per line"))
	conversation_conditions_edit = make_text_edit(92)
	right.add_child(conversation_conditions_edit)
	apply_conversation_button = make_button("Apply Conversation", apply_conversation)
	right.add_child(apply_conversation_button)
	right.add_child(HSeparator.new())
	right.add_child(make_heading("SELECTED NODE"))
	right.add_child(make_field_label("Node ID"))
	node_id_edit = LineEdit.new()
	node_id_edit.editable = false
	right.add_child(node_id_edit)
	node_kind_label = Label.new()
	node_kind_label.modulate = Color("e1c46e")
	right.add_child(node_kind_label)
	right.add_child(make_field_label("Speaker"))
	node_speaker_edit = LineEdit.new()
	right.add_child(node_speaker_edit)
	right.add_child(make_field_label("Line text · text or era-keyed JSON object"))
	node_text_edit = make_text_edit(92)
	right.add_child(node_text_edit)
	right.add_child(make_field_label("Next node"))
	node_next_selector = OptionButton.new()
	right.add_child(node_next_selector)
	right.add_child(make_field_label("Choice prompt · text or era-keyed JSON object"))
	node_prompt_edit = make_text_edit(70)
	right.add_child(node_prompt_edit)
	right.add_child(make_field_label("Choices · one complete JSON object per line"))
	node_choices_edit = make_text_edit(150)
	right.add_child(node_choices_edit)
	right.add_child(make_field_label("Node conditions · one JSON object per line"))
	node_conditions_edit = make_text_edit(90)
	right.add_child(node_conditions_edit)
	right.add_child(make_field_label("Node effects · one JSON object per line"))
	node_effects_edit = make_text_edit(110)
	right.add_child(node_effects_edit)
	apply_node_button = make_button("Apply Node", apply_node)
	right.add_child(apply_node_button)
	set_conversation_form_enabled(false)
	set_node_form_enabled(false)


func build_quest_tab() -> void:
	var tab := HSplitContainer.new()
	tab.name = "Quests"
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 290
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("QUESTS"))
	quest_list = ItemList.new()
	quest_list.custom_minimum_size.y = 190
	quest_list.item_selected.connect(on_quest_selected)
	left.add_child(quest_list)
	new_quest_id = LineEdit.new()
	new_quest_id.placeholder_text = "new_quest_id"
	left.add_child(new_quest_id)
	var quest_buttons := HBoxContainer.new()
	quest_buttons.add_child(make_button("Add", add_quest))
	delete_quest_button = make_button("Delete", delete_quest)
	quest_buttons.add_child(delete_quest_button)
	left.add_child(quest_buttons)
	left.add_child(HSeparator.new())
	left.add_child(make_heading("STAGES"))
	stage_list = ItemList.new()
	stage_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_list.item_selected.connect(on_stage_selected)
	left.add_child(stage_list)
	new_stage_id = LineEdit.new()
	new_stage_id.placeholder_text = "new_stage_id"
	left.add_child(new_stage_id)
	var stage_buttons := HBoxContainer.new()
	stage_buttons.add_child(make_button("Add Stage", add_stage))
	delete_stage_button = make_button("Delete Stage", delete_stage)
	stage_buttons.add_child(delete_stage_button)
	left.add_child(stage_buttons)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	right_scroll.add_child(right)
	right.add_child(make_heading("QUEST DEFINITION"))
	right.add_child(make_field_label("Title"))
	quest_title_edit = LineEdit.new()
	right.add_child(quest_title_edit)
	right.add_child(make_field_label("Summary"))
	quest_summary_edit = make_text_edit(92)
	right.add_child(quest_summary_edit)
	quest_auto_start = CheckBox.new()
	quest_auto_start.text = "Start automatically when the campaign begins"
	right.add_child(quest_auto_start)
	right.add_child(make_field_label("Initial stage"))
	quest_initial_stage_selector = OptionButton.new()
	right.add_child(quest_initial_stage_selector)
	right.add_child(make_field_label("Completion rewards · one JSON effect per line"))
	quest_rewards_edit = make_text_edit(130)
	right.add_child(quest_rewards_edit)
	apply_quest_button = make_button("Apply Quest", apply_quest)
	right.add_child(apply_quest_button)
	right.add_child(HSeparator.new())
	right.add_child(make_heading("SELECTED STAGE"))
	right.add_child(make_field_label("Stage ID"))
	stage_id_edit = LineEdit.new()
	stage_id_edit.editable = false
	right.add_child(stage_id_edit)
	right.add_child(make_field_label("Objective description"))
	stage_description_edit = make_text_edit(92)
	right.add_child(stage_description_edit)
	right.add_child(make_field_label("Next stage · blank completes quest"))
	stage_next_selector = OptionButton.new()
	right.add_child(stage_next_selector)
	right.add_child(make_field_label("Completion conditions · one JSON condition per line"))
	stage_conditions_edit = make_text_edit(150)
	right.add_child(stage_conditions_edit)
	apply_stage_button = make_button("Apply Stage", apply_stage)
	right.add_child(apply_stage_button)
	set_quest_form_enabled(false)
	set_stage_form_enabled(false)


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color("e0c16c")
	return label


func make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color("aeb8c2")
	return label


func make_text_edit(height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


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
		clear_all()
		set_status("No source campaigns found under res://campaigns.", true)
		return
	campaign_selector.select(selected_index)
	on_campaign_selected(selected_index)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	var story_result := StoryCatalog.load_catalogs(active_campaign_path, active_campaign)
	if not story_result.get("ok", false):
		set_status(format_messages(story_result.get("errors", [])), true)
		return
	var files: Array = story_result.get("files", [])
	if files.is_empty():
		active_story_path = StoryCatalog.primary_catalog_path(active_campaign_path, active_campaign)
		active_story_catalog = StoryCatalog.default_story_catalog()
	else:
		var file_record: Dictionary = files[0]
		active_story_path = str(file_record.get("path", ""))
		active_story_catalog = file_record.get("data", {})
	rebuild_definitions()
	refresh_all()
	set_status("Loaded story data for '%s'." % active_campaign.get("title", active_campaign.get("id", "campaign")), false)


func rebuild_definitions() -> void:
	conversation_definitions.clear()
	quest_definitions.clear()
	for value in active_story_catalog.get("conversations", []):
		if typeof(value) == TYPE_DICTIONARY:
			var record: Dictionary = value
			var identifier := str(record.get("id", ""))
			if not identifier.is_empty():
				conversation_definitions[identifier] = record
	for value in active_story_catalog.get("quests", []):
		if typeof(value) == TYPE_DICTIONARY:
			var record: Dictionary = value
			var identifier := str(record.get("id", ""))
			if not identifier.is_empty():
				quest_definitions[identifier] = record


func refresh_all() -> void:
	refresh_conversation_list(selected_conversation_id)
	refresh_quest_list(selected_quest_id)


func sorted_ids(definitions: Dictionary, label_field: String) -> PackedStringArray:
	var ids: Array[String] = []
	for identifier in definitions.keys():
		ids.append(str(identifier))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_data: Dictionary = definitions.get(left, {})
		var right_data: Dictionary = definitions.get(right, {})
		return str(left_data.get(label_field, left)).naturalnocasecmp_to(str(right_data.get(label_field, right))) < 0
	)
	return PackedStringArray(ids)


func refresh_conversation_list(preferred_id: String = "") -> void:
	conversation_list.clear()
	var ids := sorted_ids(conversation_definitions, "display_name")
	for conversation_id in ids:
		var data := StoryCatalog.conversation(conversation_definitions, conversation_id)
		var index := conversation_list.item_count
		conversation_list.add_item(str(data.get("display_name", conversation_id)))
		conversation_list.set_item_metadata(index, conversation_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_conversation_id(preferred_id)


func on_conversation_selected(index: int) -> void:
	if index >= 0 and index < conversation_list.item_count:
		select_conversation_id(str(conversation_list.get_item_metadata(index)))


func select_conversation_id(conversation_id: String) -> void:
	selected_conversation_id = conversation_id if conversation_definitions.has(conversation_id) else ""
	for index in range(conversation_list.item_count):
		if str(conversation_list.get_item_metadata(index)) == selected_conversation_id:
			conversation_list.select(index)
			break
	populate_conversation_form()
	refresh_node_list(selected_node_id)
	refresh_graph_preview()


func populate_conversation_form() -> void:
	var data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	if data.is_empty():
		set_conversation_form_enabled(false)
		conversation_name_edit.text = ""
		conversation_conditions_edit.text = ""
		conversation_start_selector.clear()
		return
	set_conversation_form_enabled(true)
	conversation_name_edit.text = str(data.get("display_name", ""))
	populate_node_selector(conversation_start_selector, data, false)
	select_option_metadata(conversation_start_selector, str(data.get("start_node", "")))
	conversation_conditions_edit.text = format_json_lines(StoryCatalog.conditions(data))


func refresh_node_list(preferred_id: String = "") -> void:
	node_list.clear()
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	var node_records := StoryCatalog.nodes(conversation_data)
	for value in node_records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = value
		var node_id := str(data.get("id", ""))
		var index := node_list.item_count
		node_list.add_item("%s  ·  %s" % [node_id, str(data.get("kind", "line")).to_upper()])
		node_list.set_item_metadata(index, node_id)
	if preferred_id.is_empty() and not node_records.is_empty() and typeof(node_records[0]) == TYPE_DICTIONARY:
		preferred_id = str((node_records[0] as Dictionary).get("id", ""))
	select_node_id(preferred_id)


func on_node_selected(index: int) -> void:
	if index >= 0 and index < node_list.item_count:
		select_node_id(str(node_list.get_item_metadata(index)))


func select_node_id(node_id: String) -> void:
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	selected_node_id = node_id if StoryCatalog.node_index(conversation_data).has(node_id) else ""
	for index in range(node_list.item_count):
		if str(node_list.get_item_metadata(index)) == selected_node_id:
			node_list.select(index)
			break
	populate_node_form()
	select_graph_node(selected_node_id)


func populate_node_form() -> void:
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	var data := StoryCatalog.node(conversation_data, selected_node_id)
	if data.is_empty():
		set_node_form_enabled(false)
		clear_node_form()
		return
	set_node_form_enabled(true)
	var kind := str(data.get("kind", "line"))
	node_id_edit.text = selected_node_id
	node_kind_label.text = "KIND: %s" % kind.to_upper()
	node_speaker_edit.text = str(data.get("speaker", ""))
	node_text_edit.text = format_text_value(data.get("text", ""))
	populate_node_selector(node_next_selector, conversation_data, true)
	select_option_metadata(node_next_selector, str(data.get("next", "")))
	node_prompt_edit.text = format_text_value(data.get("prompt", ""))
	node_choices_edit.text = format_json_lines(StoryCatalog.choices(data))
	node_conditions_edit.text = format_json_lines(StoryCatalog.conditions(data))
	node_effects_edit.text = format_json_lines(StoryCatalog.effects(data))
	var is_line := kind == "line"
	var is_choice := kind == "choice"
	node_speaker_edit.editable = is_line
	node_text_edit.editable = is_line
	node_next_selector.disabled = not is_line
	node_prompt_edit.editable = is_choice
	node_choices_edit.editable = is_choice


func clear_node_form() -> void:
	node_id_edit.text = ""
	node_kind_label.text = ""
	node_speaker_edit.text = ""
	node_text_edit.text = ""
	node_prompt_edit.text = ""
	node_choices_edit.text = ""
	node_conditions_edit.text = ""
	node_effects_edit.text = ""
	node_next_selector.clear()


func populate_node_selector(selector: OptionButton, conversation_data: Dictionary, include_blank: bool) -> void:
	selector.clear()
	if include_blank:
		selector.add_item("(END CONVERSATION)")
		selector.set_item_metadata(0, "")
	for value in StoryCatalog.nodes(conversation_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = value
		var node_id := str(data.get("id", ""))
		var index := selector.item_count
		selector.add_item(node_id)
		selector.set_item_metadata(index, node_id)


func refresh_graph_preview() -> void:
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.free()
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	if conversation_data.is_empty():
		return
	var start_node := str(conversation_data.get("start_node", ""))
	var node_records := StoryCatalog.nodes(conversation_data)
	var fallback_index := 0
	for value in node_records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = value
		var node_id := str(data.get("id", ""))
		if node_id.is_empty():
			continue
		var graph_node := GraphNode.new()
		graph_node.name = StringName(node_id)
		var kind := str(data.get("kind", "line"))
		graph_node.title = "%s · %s" % [kind.to_upper(), node_id]
		graph_node.custom_minimum_size = Vector2(230, 0)
		var default_position := Vector2(80 + (fallback_index % 3) * 320, 80 + floori(fallback_index / 3.0) * 190)
		graph_node.position_offset = Repository.data_to_vector(data.get("editor_position"), default_position)
		fallback_index += 1
		var has_input := node_id != start_node
		if kind == "choice":
			var prompt := Label.new()
			prompt.text = StoryCatalog.choice_prompt(data, "default")
			prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			prompt.custom_minimum_size.x = 205
			graph_node.add_child(prompt)
			graph_node.set_slot(0, has_input, 0, Color("8fb3c9"), false, 0, Color.WHITE)
			var choice_index := 0
			for choice_value in StoryCatalog.choices(data):
				if typeof(choice_value) != TYPE_DICTIONARY:
					continue
				var choice: Dictionary = choice_value
				var row := Label.new()
				row.text = "• %s" % StoryCatalog.resolved_text(choice.get("text", ""), "default", "Choice")
				row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row.custom_minimum_size.x = 205
				graph_node.add_child(row)
				graph_node.set_slot(choice_index + 1, false, 0, Color.WHITE, true, 0, Color("e0bd66"))
				choice_index += 1
		elif kind == "end":
			var end_label := Label.new()
			end_label.text = "Conversation closes"
			graph_node.add_child(end_label)
			graph_node.set_slot(0, has_input, 0, Color("8fb3c9"), false, 0, Color.WHITE)
		else:
			var line_label := Label.new()
			var speaker := str(data.get("speaker", "")).strip_edges()
			var text := StoryCatalog.node_text(data, "default")
			line_label.text = "%s%s" % [(speaker + ":\n") if not speaker.is_empty() else "", text]
			line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line_label.custom_minimum_size.x = 205
			graph_node.add_child(line_label)
			graph_node.set_slot(0, has_input, 0, Color("8fb3c9"), not str(data.get("next", "")).is_empty(), 0, Color("e0bd66"))
		graph.add_child(graph_node)
		if graph_node.has_signal("position_offset_changed"):
			graph_node.connect("position_offset_changed", Callable(self, "on_graph_node_moved").bind(node_id, graph_node))
	for value in node_records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = value
		var node_id := str(data.get("id", ""))
		var kind := str(data.get("kind", "line"))
		if kind == "line":
			connect_graph_nodes(node_id, 0, str(data.get("next", "")))
		elif kind == "choice":
			var output_port := 0
			for choice_value in StoryCatalog.choices(data):
				if typeof(choice_value) == TYPE_DICTIONARY:
					connect_graph_nodes(node_id, output_port, str((choice_value as Dictionary).get("next", "")))
					output_port += 1
	select_graph_node(selected_node_id)


func connect_graph_nodes(from_id: String, from_port: int, to_id: String) -> void:
	if from_id.is_empty() or to_id.is_empty():
		return
	if not graph.has_node(NodePath(from_id)) or not graph.has_node(NodePath(to_id)):
		return
	graph.connect_node(StringName(from_id), from_port, StringName(to_id), 0)


func on_graph_node_selected(node: Node) -> void:
	if node is GraphNode:
		select_node_id(str(node.name))


func on_graph_node_moved(node_id: String, graph_node: GraphNode) -> void:
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	var nodes: Array = conversation_data.get("nodes", [])
	for index in range(nodes.size()):
		if typeof(nodes[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = nodes[index]
		if str(data.get("id", "")) != node_id:
			continue
		data["editor_position"] = Repository.vector_to_data(graph_node.position_offset)
		nodes[index] = data
		conversation_data["nodes"] = nodes
		update_conversation_record(conversation_data)
		return


func select_graph_node(node_id: String) -> void:
	for child in graph.get_children():
		if child is GraphNode:
			(child as GraphNode).selected = str(child.name) == node_id


func add_conversation() -> void:
	var conversation_id := Repository.normalise_id(new_conversation_id.text)
	if conversation_id.is_empty():
		set_status("Enter a valid conversation ID.", true)
		return
	if conversation_definitions.has(conversation_id):
		set_status("Conversation '%s' already exists." % conversation_id, true)
		return
	var records: Array = active_story_catalog.get("conversations", [])
	records.append(StoryCatalog.default_conversation(conversation_id, conversation_id.replace("_", " ").capitalize()))
	active_story_catalog["conversations"] = records
	new_conversation_id.clear()
	if save_story_catalog():
		selected_conversation_id = conversation_id
		selected_node_id = "opening"
		refresh_all()
		set_status("Created conversation '%s'." % conversation_id, false)


func delete_conversation() -> void:
	if selected_conversation_id.is_empty():
		return
	var usages := conversation_usages(selected_conversation_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; referenced by %s." % [selected_conversation_id, ", ".join(usages)], true)
		return
	var records: Array = active_story_catalog.get("conversations", [])
	for index in range(records.size() - 1, -1, -1):
		if typeof(records[index]) == TYPE_DICTIONARY and str((records[index] as Dictionary).get("id", "")) == selected_conversation_id:
			records.remove_at(index)
			break
	active_story_catalog["conversations"] = records
	var deleted_id := selected_conversation_id
	selected_conversation_id = ""
	selected_node_id = ""
	if save_story_catalog():
		refresh_all()
		set_status("Deleted conversation '%s'." % deleted_id, false)


func conversation_usages(conversation_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	var object_result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	for object_id in object_result.get("definitions", {}).keys():
		var object_data: Dictionary = object_result.get("definitions", {}).get(object_id, {})
		if str(object_data.get("conversation_id", "")) == conversation_id:
			usages.append("object:%s" % object_id)
	for relative_value in active_campaign.get("map_files", []):
		var path := active_campaign_path.get_base_dir().path_join(str(relative_value))
		var result := Repository.read_json(path)
		if not result.get("ok", false):
			continue
		var map_data: Dictionary = result.get("data", {})
		for interaction_value in map_data.get("interactions", []):
			if typeof(interaction_value) == TYPE_DICTIONARY:
				var interaction: Dictionary = interaction_value
				if str(interaction.get("conversation_id", "")) == conversation_id:
					usages.append("%s:%s" % [map_data.get("id", "map"), interaction.get("id", "interaction")])
	return usages


func add_node(kind: String) -> void:
	if selected_conversation_id.is_empty():
		return
	var node_id := Repository.normalise_id(new_node_id.text)
	if node_id.is_empty():
		set_status("Enter a valid node ID.", true)
		return
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	if StoryCatalog.node_index(conversation_data).has(node_id):
		set_status("Node '%s' already exists." % node_id, true)
		return
	var record: Dictionary = {
		"id": node_id,
		"kind": kind,
		"conditions": [],
		"effects": [],
		"editor_position": {"x": 120 + StoryCatalog.nodes(conversation_data).size() * 90, "y": 160}
	}
	if kind == "line":
		record["speaker"] = "SPEAKER"
		record["text"] = "New dialogue line."
		record["next"] = ""
	elif kind == "choice":
		record["prompt"] = "Choose a response."
		record["choices"] = [{"id": "continue", "text": "Continue.", "conditions": [], "effects": [], "next": ""}]
	var nodes: Array = conversation_data.get("nodes", [])
	nodes.append(record)
	conversation_data["nodes"] = nodes
	update_conversation_record(conversation_data)
	new_node_id.clear()
	if save_story_catalog():
		selected_node_id = node_id
		refresh_all()
		set_status("Added %s node '%s'." % [kind, node_id], false)


func delete_node() -> void:
	if selected_conversation_id.is_empty() or selected_node_id.is_empty():
		return
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	if str(conversation_data.get("start_node", "")) == selected_node_id:
		set_status("The start node cannot be deleted. Select another start node first.", true)
		return
	var usages := node_usages(conversation_data, selected_node_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; referenced by %s." % [selected_node_id, ", ".join(usages)], true)
		return
	var nodes: Array = conversation_data.get("nodes", [])
	for index in range(nodes.size() - 1, -1, -1):
		if typeof(nodes[index]) == TYPE_DICTIONARY and str((nodes[index] as Dictionary).get("id", "")) == selected_node_id:
			nodes.remove_at(index)
			break
	conversation_data["nodes"] = nodes
	update_conversation_record(conversation_data)
	var deleted_id := selected_node_id
	selected_node_id = ""
	if save_story_catalog():
		refresh_all()
		set_status("Deleted node '%s'." % deleted_id, false)


func node_usages(conversation_data: Dictionary, node_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for value in StoryCatalog.nodes(conversation_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = value
		var source_id := str(data.get("id", "node"))
		if str(data.get("next", "")) == node_id:
			usages.append("node:%s" % source_id)
		for choice_value in StoryCatalog.choices(data):
			if typeof(choice_value) == TYPE_DICTIONARY and str((choice_value as Dictionary).get("next", "")) == node_id:
				usages.append("choice:%s/%s" % [source_id, (choice_value as Dictionary).get("id", "choice")])
	return usages


func apply_conversation() -> void:
	if selected_conversation_id.is_empty():
		return
	var parsed := parse_json_lines(conversation_conditions_edit.text, "conversation conditions")
	if not parsed.get("ok", false):
		set_status(format_messages(parsed.get("errors", [])), true)
		return
	var data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	data["display_name"] = conversation_name_edit.text.strip_edges()
	data["start_node"] = selected_option_metadata(conversation_start_selector)
	data["conditions"] = parsed.get("entries", [])
	update_conversation_record(data)
	if save_story_catalog():
		refresh_all()
		set_status("Updated conversation '%s'." % selected_conversation_id, false)


func apply_node() -> void:
	if selected_conversation_id.is_empty() or selected_node_id.is_empty():
		return
	var conditions_result := parse_json_lines(node_conditions_edit.text, "node conditions")
	var effects_result := parse_json_lines(node_effects_edit.text, "node effects")
	if not conditions_result.get("ok", false) or not effects_result.get("ok", false):
		var errors: Array = []
		errors.append_array(conditions_result.get("errors", []))
		errors.append_array(effects_result.get("errors", []))
		set_status(format_messages(errors), true)
		return
	var conversation_data := StoryCatalog.conversation(conversation_definitions, selected_conversation_id)
	var nodes: Array = conversation_data.get("nodes", [])
	for index in range(nodes.size()):
		if typeof(nodes[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = nodes[index]
		if str(data.get("id", "")) != selected_node_id:
			continue
		var kind := str(data.get("kind", "line"))
		data["conditions"] = conditions_result.get("entries", [])
		data["effects"] = effects_result.get("entries", [])
		if kind == "line":
			var text_result := parse_text_value(node_text_edit.text, "line text")
			if not text_result.get("ok", false):
				set_status(format_messages(text_result.get("errors", [])), true)
				return
			data["speaker"] = node_speaker_edit.text.strip_edges()
			data["text"] = text_result.get("value", "")
			data["next"] = selected_option_metadata(node_next_selector)
		elif kind == "choice":
			var prompt_result := parse_text_value(node_prompt_edit.text, "choice prompt")
			var choices_result := parse_json_lines(node_choices_edit.text, "choices")
			if not prompt_result.get("ok", false) or not choices_result.get("ok", false):
				var errors: Array = []
				errors.append_array(prompt_result.get("errors", []))
				errors.append_array(choices_result.get("errors", []))
				set_status(format_messages(errors), true)
				return
			data["prompt"] = prompt_result.get("value", "")
			data["choices"] = choices_result.get("entries", [])
		nodes[index] = data
		break
	conversation_data["nodes"] = nodes
	update_conversation_record(conversation_data)
	if save_story_catalog():
		refresh_all()
		set_status("Updated node '%s'." % selected_node_id, false)


func update_conversation_record(conversation_data: Dictionary) -> void:
	var records: Array = active_story_catalog.get("conversations", [])
	for index in range(records.size()):
		if typeof(records[index]) == TYPE_DICTIONARY and str((records[index] as Dictionary).get("id", "")) == str(conversation_data.get("id", "")):
			records[index] = conversation_data
			break
	active_story_catalog["conversations"] = records
	rebuild_definitions()


func refresh_quest_list(preferred_id: String = "") -> void:
	quest_list.clear()
	var ids := sorted_ids(quest_definitions, "title")
	for quest_id in ids:
		var data := StoryCatalog.quest(quest_definitions, quest_id)
		var index := quest_list.item_count
		quest_list.add_item(str(data.get("title", quest_id)))
		quest_list.set_item_metadata(index, quest_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_quest_id(preferred_id)


func on_quest_selected(index: int) -> void:
	if index >= 0 and index < quest_list.item_count:
		select_quest_id(str(quest_list.get_item_metadata(index)))


func select_quest_id(quest_id: String) -> void:
	selected_quest_id = quest_id if quest_definitions.has(quest_id) else ""
	for index in range(quest_list.item_count):
		if str(quest_list.get_item_metadata(index)) == selected_quest_id:
			quest_list.select(index)
			break
	populate_quest_form()
	refresh_stage_list(selected_stage_id)


func populate_quest_form() -> void:
	var data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	if data.is_empty():
		set_quest_form_enabled(false)
		quest_title_edit.text = ""
		quest_summary_edit.text = ""
		quest_rewards_edit.text = ""
		quest_initial_stage_selector.clear()
		return
	set_quest_form_enabled(true)
	quest_title_edit.text = str(data.get("title", ""))
	quest_summary_edit.text = str(data.get("summary", ""))
	quest_auto_start.button_pressed = bool(data.get("auto_start", false))
	populate_stage_selector(quest_initial_stage_selector, data, false)
	select_option_metadata(quest_initial_stage_selector, str(data.get("initial_stage", "")))
	quest_rewards_edit.text = format_json_lines(StoryCatalog.effects(data, "rewards"))


func refresh_stage_list(preferred_id: String = "") -> void:
	stage_list.clear()
	var quest_data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	var records := StoryCatalog.stages(quest_data)
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = value
		var stage_id := str(data.get("id", ""))
		var index := stage_list.item_count
		stage_list.add_item(stage_id)
		stage_list.set_item_metadata(index, stage_id)
	if preferred_id.is_empty() and not records.is_empty() and typeof(records[0]) == TYPE_DICTIONARY:
		preferred_id = str((records[0] as Dictionary).get("id", ""))
	select_stage_id(preferred_id)


func on_stage_selected(index: int) -> void:
	if index >= 0 and index < stage_list.item_count:
		select_stage_id(str(stage_list.get_item_metadata(index)))


func select_stage_id(stage_id: String) -> void:
	var quest_data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	selected_stage_id = stage_id if StoryCatalog.stage_index(quest_data).has(stage_id) else ""
	for index in range(stage_list.item_count):
		if str(stage_list.get_item_metadata(index)) == selected_stage_id:
			stage_list.select(index)
			break
	populate_stage_form()


func populate_stage_form() -> void:
	var quest_data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	var data := StoryCatalog.stage(quest_data, selected_stage_id)
	if data.is_empty():
		set_stage_form_enabled(false)
		stage_id_edit.text = ""
		stage_description_edit.text = ""
		stage_conditions_edit.text = ""
		stage_next_selector.clear()
		return
	set_stage_form_enabled(true)
	stage_id_edit.text = selected_stage_id
	stage_description_edit.text = str(data.get("description", ""))
	populate_stage_selector(stage_next_selector, quest_data, true)
	select_option_metadata(stage_next_selector, str(data.get("next_stage", "")))
	stage_conditions_edit.text = format_json_lines(StoryCatalog.conditions(data, "completion_conditions"))


func populate_stage_selector(selector: OptionButton, quest_data: Dictionary, include_blank: bool) -> void:
	selector.clear()
	if include_blank:
		selector.add_item("(COMPLETE QUEST)")
		selector.set_item_metadata(0, "")
	for value in StoryCatalog.stages(quest_data):
		if typeof(value) == TYPE_DICTIONARY:
			var stage_id := str((value as Dictionary).get("id", ""))
			var index := selector.item_count
			selector.add_item(stage_id)
			selector.set_item_metadata(index, stage_id)


func add_quest() -> void:
	var quest_id := Repository.normalise_id(new_quest_id.text)
	if quest_id.is_empty():
		set_status("Enter a valid quest ID.", true)
		return
	if quest_definitions.has(quest_id):
		set_status("Quest '%s' already exists." % quest_id, true)
		return
	var records: Array = active_story_catalog.get("quests", [])
	records.append(StoryCatalog.default_quest(quest_id, quest_id.replace("_", " ").capitalize()))
	active_story_catalog["quests"] = records
	new_quest_id.clear()
	if save_story_catalog():
		selected_quest_id = quest_id
		selected_stage_id = "investigate"
		refresh_all()
		set_status("Created quest '%s'." % quest_id, false)


func delete_quest() -> void:
	if selected_quest_id.is_empty():
		return
	var usages := quest_usages(selected_quest_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; referenced by %s." % [selected_quest_id, ", ".join(usages)], true)
		return
	var records: Array = active_story_catalog.get("quests", [])
	for index in range(records.size() - 1, -1, -1):
		if typeof(records[index]) == TYPE_DICTIONARY and str((records[index] as Dictionary).get("id", "")) == selected_quest_id:
			records.remove_at(index)
			break
	active_story_catalog["quests"] = records
	var deleted_id := selected_quest_id
	selected_quest_id = ""
	selected_stage_id = ""
	if save_story_catalog():
		refresh_all()
		set_status("Deleted quest '%s'." % deleted_id, false)


func quest_usages(quest_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for value in active_campaign.get("starting_quests", []):
		if str(value) == quest_id:
			usages.append("starting_quests")
	for conversation_value in active_story_catalog.get("conversations", []):
		if value_references_quest(conversation_value, quest_id):
			usages.append("conversation:%s" % (conversation_value as Dictionary).get("id", "conversation"))
	for quest_value in active_story_catalog.get("quests", []):
		if typeof(quest_value) != TYPE_DICTIONARY:
			continue
		var other: Dictionary = quest_value
		if str(other.get("id", "")) == quest_id:
			continue
		if value_references_quest(other, quest_id):
			usages.append("quest:%s" % other.get("id", "quest"))
	return usages


func value_references_quest(value: Variant, quest_id: String, stage_id: String = "") -> bool:
	if typeof(value) == TYPE_ARRAY:
		for child in value:
			if value_references_quest(child, quest_id, stage_id):
				return true
		return false
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = value
	if str(data.get("quest_id", "")) == quest_id:
		return stage_id.is_empty() or str(data.get("stage_id", "")) == stage_id
	for child in data.values():
		if value_references_quest(child, quest_id, stage_id):
			return true
	return false


func add_stage() -> void:
	if selected_quest_id.is_empty():
		return
	var stage_id := Repository.normalise_id(new_stage_id.text)
	if stage_id.is_empty():
		set_status("Enter a valid stage ID.", true)
		return
	var quest_data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	if StoryCatalog.stage_index(quest_data).has(stage_id):
		set_status("Stage '%s' already exists." % stage_id, true)
		return
	var stages: Array = quest_data.get("stages", [])
	stages.append({
		"id": stage_id,
		"description": "Complete the authored objective.",
		"completion_conditions": [
			{"type": "state_equals", "key": "quest:%s:%s:complete" % [selected_quest_id, stage_id], "value": true}
		],
		"next_stage": ""
	})
	quest_data["stages"] = stages
	update_quest_record(quest_data)
	new_stage_id.clear()
	if save_story_catalog():
		selected_stage_id = stage_id
		refresh_all()
		set_status("Added stage '%s'." % stage_id, false)


func delete_stage() -> void:
	if selected_quest_id.is_empty() or selected_stage_id.is_empty():
		return
	var quest_data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	if str(quest_data.get("initial_stage", "")) == selected_stage_id:
		set_status("The initial stage cannot be deleted. Select another initial stage first.", true)
		return
	var usages := stage_usages(selected_quest_id, selected_stage_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; referenced by %s." % [selected_stage_id, ", ".join(usages)], true)
		return
	var stages: Array = quest_data.get("stages", [])
	for index in range(stages.size() - 1, -1, -1):
		if typeof(stages[index]) == TYPE_DICTIONARY and str((stages[index] as Dictionary).get("id", "")) == selected_stage_id:
			stages.remove_at(index)
			break
	quest_data["stages"] = stages
	update_quest_record(quest_data)
	var deleted_id := selected_stage_id
	selected_stage_id = ""
	if save_story_catalog():
		refresh_all()
		set_status("Deleted stage '%s'." % deleted_id, false)


func stage_usages(quest_id: String, stage_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for conversation_value in active_story_catalog.get("conversations", []):
		if value_references_quest(conversation_value, quest_id, stage_id):
			usages.append("conversation:%s" % (conversation_value as Dictionary).get("id", "conversation"))
	for quest_value in active_story_catalog.get("quests", []):
		if typeof(quest_value) != TYPE_DICTIONARY:
			continue
		var quest_data: Dictionary = quest_value
		for stage_value in StoryCatalog.stages(quest_data):
			if typeof(stage_value) == TYPE_DICTIONARY:
				var stage_data: Dictionary = stage_value
				if str(stage_data.get("next_stage", "")) == stage_id and str(stage_data.get("id", "")) != stage_id and str(quest_data.get("id", "")) == quest_id:
					usages.append("next_stage:%s" % stage_data.get("id", "stage"))
		if value_references_quest(quest_data, quest_id, stage_id) and str(quest_data.get("id", "")) != quest_id:
			usages.append("quest:%s" % quest_data.get("id", "quest"))
	return usages


func apply_quest() -> void:
	if selected_quest_id.is_empty():
		return
	var rewards_result := parse_json_lines(quest_rewards_edit.text, "quest rewards")
	if not rewards_result.get("ok", false):
		set_status(format_messages(rewards_result.get("errors", [])), true)
		return
	var data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	data["title"] = quest_title_edit.text.strip_edges()
	data["summary"] = quest_summary_edit.text.strip_edges()
	data["auto_start"] = quest_auto_start.button_pressed
	data["initial_stage"] = selected_option_metadata(quest_initial_stage_selector)
	data["rewards"] = rewards_result.get("entries", [])
	update_quest_record(data)
	if save_story_catalog():
		refresh_all()
		set_status("Updated quest '%s'." % selected_quest_id, false)


func apply_stage() -> void:
	if selected_quest_id.is_empty() or selected_stage_id.is_empty():
		return
	var conditions_result := parse_json_lines(stage_conditions_edit.text, "stage completion conditions")
	if not conditions_result.get("ok", false):
		set_status(format_messages(conditions_result.get("errors", [])), true)
		return
	var quest_data := StoryCatalog.quest(quest_definitions, selected_quest_id)
	var stages: Array = quest_data.get("stages", [])
	for index in range(stages.size()):
		if typeof(stages[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = stages[index]
		if str(data.get("id", "")) != selected_stage_id:
			continue
		data["description"] = stage_description_edit.text.strip_edges()
		data["completion_conditions"] = conditions_result.get("entries", [])
		data["next_stage"] = selected_option_metadata(stage_next_selector)
		stages[index] = data
		break
	quest_data["stages"] = stages
	update_quest_record(quest_data)
	if save_story_catalog():
		refresh_all()
		set_status("Updated stage '%s'." % selected_stage_id, false)


func update_quest_record(quest_data: Dictionary) -> void:
	var records: Array = active_story_catalog.get("quests", [])
	for index in range(records.size()):
		if typeof(records[index]) == TYPE_DICTIONARY and str((records[index] as Dictionary).get("id", "")) == str(quest_data.get("id", "")):
			records[index] = quest_data
			break
	active_story_catalog["quests"] = records
	rebuild_definitions()


func save_story_catalog() -> bool:
	if active_story_path.is_empty():
		set_status("No editable story catalog is available.", true)
		return false
	var previous_result := Repository.read_json(active_story_path)
	var previous: Dictionary = previous_result.get("data", {}) if previous_result.get("ok", false) else {}
	var save_result := Repository.save_json(active_story_path, active_story_catalog)
	if not save_result.get("ok", false):
		set_status(format_messages(save_result.get("errors", [])), true)
		return false
	var report := StoryValidator.validate_campaign_path(active_campaign_path)
	if not report.get("ok", false):
		if not previous.is_empty():
			Repository.save_json(active_story_path, previous)
			active_story_catalog = previous
			rebuild_definitions()
		set_status("Story save rolled back.\n%s" % format_report(report), true)
		return false
	rescan_editor_files()
	if not report.get("warnings", []).is_empty():
		set_status(format_report(report), false)
	return true


func parse_json_lines(text: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	var line_number := 0
	for raw_line in text.split("\n"):
		line_number += 1
		var line := str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(line)
		if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
			errors.append("%s line %d must be one valid JSON object." % [label, line_number])
			continue
		entries.append(parser.data)
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func format_json_lines(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var lines := PackedStringArray()
	for record in value:
		if typeof(record) == TYPE_DICTIONARY:
			lines.append(JSON.stringify(record, "", true))
	return "\n".join(lines)


func parse_text_value(text: String, label: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "value": "", "errors": ["%s cannot be empty." % label]}
	if trimmed.begins_with("{"):
		var parser := JSON.new()
		var parse_error := parser.parse(trimmed)
		if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return {"ok": false, "value": "", "errors": ["%s must be plain text or one valid JSON object." % label]}
		return {"ok": true, "value": parser.data, "errors": []}
	return {"ok": true, "value": text.strip_edges(), "errors": []}


func format_text_value(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return JSON.stringify(value, "\t", true)
	return str(value)


func select_option_metadata(selector: OptionButton, value: String) -> void:
	for index in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == value:
			selector.select(index)
			return
	if selector.item_count > 0:
		selector.select(0)


func selected_option_metadata(selector: OptionButton) -> String:
	if selector.item_count == 0 or selector.selected < 0:
		return ""
	return str(selector.get_item_metadata(selector.selected))


func set_conversation_form_enabled(enabled: bool) -> void:
	conversation_name_edit.editable = enabled
	conversation_start_selector.disabled = not enabled
	conversation_conditions_edit.editable = enabled
	apply_conversation_button.disabled = not enabled
	delete_conversation_button.disabled = not enabled


func set_node_form_enabled(enabled: bool) -> void:
	node_speaker_edit.editable = enabled
	node_text_edit.editable = enabled
	node_next_selector.disabled = not enabled
	node_prompt_edit.editable = enabled
	node_choices_edit.editable = enabled
	node_conditions_edit.editable = enabled
	node_effects_edit.editable = enabled
	apply_node_button.disabled = not enabled
	delete_node_button.disabled = not enabled


func set_quest_form_enabled(enabled: bool) -> void:
	quest_title_edit.editable = enabled
	quest_summary_edit.editable = enabled
	quest_auto_start.disabled = not enabled
	quest_initial_stage_selector.disabled = not enabled
	quest_rewards_edit.editable = enabled
	apply_quest_button.disabled = not enabled
	delete_quest_button.disabled = not enabled


func set_stage_form_enabled(enabled: bool) -> void:
	stage_description_edit.editable = enabled
	stage_next_selector.disabled = not enabled
	stage_conditions_edit.editable = enabled
	apply_stage_button.disabled = not enabled
	delete_stage_button.disabled = not enabled


func validate_all() -> void:
	var report := StoryValidator.validate_all()
	set_status(format_report(report), not report.get("ok", false))


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d map(s), %d conversation(s), %d quest(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 1 if not active_campaign.is_empty() else 0),
			report.get("map_count", active_campaign.get("map_files", []).size()),
			report.get("conversation_count", conversation_definitions.size()),
			report.get("quest_count", quest_definitions.size()),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	for warning in report.get("warnings", []):
		lines.append("WARNING: %s" % warning)
	for error in report.get("errors", []):
		lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func format_messages(messages: Array) -> String:
	var lines := PackedStringArray()
	for message in messages:
		lines.append(str(message))
	return "\n".join(lines)


func set_status(message: String, is_error: bool) -> void:
	var color := "#ff9797" if is_error else "#acd8b2"
	status_label.text = "[color=%s]%s[/color]" % [color, message]


func rescan_editor_files() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func open_story_folder() -> void:
	var directory := active_campaign_path.get_base_dir().path_join("story") if not active_campaign_path.is_empty() else Repository.DEFAULT_ROOT
	var absolute_path := ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(absolute_path)
	OS.shell_open(absolute_path)


func clear_all() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_story_catalog = {}
	active_story_path = ""
	conversation_definitions.clear()
	quest_definitions.clear()
	selected_conversation_id = ""
	selected_node_id = ""
	selected_quest_id = ""
	selected_stage_id = ""
	conversation_list.clear()
	node_list.clear()
	quest_list.clear()
	stage_list.clear()
	refresh_graph_preview()
	set_conversation_form_enabled(false)
	set_node_form_enabled(false)
	set_quest_form_enabled(false)
	set_stage_form_enabled(false)
