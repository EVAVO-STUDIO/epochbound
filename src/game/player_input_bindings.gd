@tool
extends RefCounted

const PROFILE_SCHEMA := 1
const DEVICE_KEYBOARD := "keyboard"
const DEVICE_GAMEPAD := "gamepad"
const RESERVED_ESCAPE_PHYSICAL := 4194305
const RESERVED_OPTIONS_PHYSICAL := 79
const RESERVED_START_BUTTON := 6
const CAPTURE_AXIS_THRESHOLD := 0.7
const MAX_EVENTS_PER_ACTION := 8


static func action_definitions() -> Array:
	return [
		{"id": "move_up", "label": "MOVE UP", "deadzone": 0.25, "events": [key_descriptor(87), key_descriptor(4194320), button_descriptor(11), axis_descriptor(1, -1.0)]},
		{"id": "move_down", "label": "MOVE DOWN", "deadzone": 0.25, "events": [key_descriptor(83), key_descriptor(4194322), button_descriptor(12), axis_descriptor(1, 1.0)]},
		{"id": "move_left", "label": "MOVE LEFT", "deadzone": 0.25, "events": [key_descriptor(65), key_descriptor(4194311), button_descriptor(13), axis_descriptor(0, -1.0)]},
		{"id": "move_right", "label": "MOVE RIGHT", "deadzone": 0.25, "events": [key_descriptor(68), key_descriptor(4194313), button_descriptor(14), axis_descriptor(0, 1.0)]},
		{"id": "interact", "label": "INTERACT / CONFIRM", "deadzone": 0.2, "events": [key_descriptor(69), key_descriptor(90), button_descriptor(0)]},
		{"id": "attack", "label": "ATTACK / FIRE", "deadzone": 0.2, "events": [key_descriptor(32), key_descriptor(67), button_descriptor(1)]},
		{"id": "era_shift", "label": "SHIFT ERA", "deadzone": 0.2, "events": [key_descriptor(81), key_descriptor(88), button_descriptor(2)]},
		{"id": "companion_command", "label": "MORROW COMMAND", "deadzone": 0.2, "events": [key_descriptor(82), button_descriptor(3)]},
		{"id": "companion_recall", "label": "RECALL MORROW", "deadzone": 0.2, "events": [key_descriptor(70), button_descriptor(9)]},
		{"id": "inventory_toggle", "label": "FIELD SATCHEL", "deadzone": 0.2, "events": [key_descriptor(73), button_descriptor(4)]},
		{"id": "quick_item", "label": "QUICK RESTORATIVE", "deadzone": 0.2, "events": [key_descriptor(86), button_descriptor(10)]},
		{"id": "story_journal", "label": "JOURNAL", "deadzone": 0.2, "events": [key_descriptor(74), button_descriptor(8)]},
		{"id": "save_profiles", "label": "SAVE PROFILES", "deadzone": 0.2, "events": [key_descriptor(75), button_descriptor(7)]},
		{"id": "reload_weapon", "label": "RELOAD", "deadzone": 0.2, "events": [key_descriptor(71), axis_descriptor(5, 1.0)]}
	]


static func managed_action_ids() -> PackedStringArray:
	var output := PackedStringArray()
	for value in action_definitions():
		if typeof(value) == TYPE_DICTIONARY:
			output.append(str((value as Dictionary).get("id", "")))
	return output


static func action_definition(action_id: String) -> Dictionary:
	for value in action_definitions():
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == action_id:
			return (value as Dictionary).duplicate(true)
	return {}


static func action_label(action_id: String) -> String:
	return str(action_definition(action_id).get("label", action_id.replace("_", " ").capitalize()))


static func default_profile() -> Dictionary:
	var actions: Dictionary = {}
	for value in action_definitions():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = value
		actions[str(definition.get("id", ""))] = sanitize_event_list(definition.get("events", []))
	return {"schema_version": PROFILE_SCHEMA, "actions": actions}


static func sanitize_profile(value: Variant) -> Dictionary:
	var defaults := default_profile()
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var source_actions_value: Variant = source.get("actions", {})
	var source_actions: Dictionary = source_actions_value if typeof(source_actions_value) == TYPE_DICTIONARY else {}
	var default_actions: Dictionary = defaults.get("actions", {})
	var actions: Dictionary = {}
	for action_id in managed_action_ids():
		var candidate := sanitize_event_list(source_actions.get(action_id, default_actions.get(action_id, [])))
		var fallback: Array = default_actions.get(action_id, [])
		if events_for_device(candidate, DEVICE_KEYBOARD).is_empty():
			candidate.append_array(events_for_device(fallback, DEVICE_KEYBOARD))
		if events_for_device(candidate, DEVICE_GAMEPAD).is_empty():
			candidate.append_array(events_for_device(fallback, DEVICE_GAMEPAD))
		actions[action_id] = unique_events(candidate)
	return {"schema_version": PROFILE_SCHEMA, "actions": actions}


static func validate_profile(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Input binding profile must be an object."]}
	var source: Dictionary = value
	var schema_value: Variant = source.get("schema_version", 0)
	if typeof(schema_value) != TYPE_INT:
		errors.append("Input binding schema_version must be an integer.")
	elif int(schema_value) < 0 or int(schema_value) > PROFILE_SCHEMA:
		errors.append("Input binding schema %d is unsupported." % int(schema_value))
	var actions_value: Variant = source.get("actions", {})
	if typeof(actions_value) != TYPE_DICTIONARY:
		errors.append("Input binding actions must be an object.")
		return {"ok": false, "errors": errors}
	var actions: Dictionary = actions_value
	var managed_ids := managed_action_ids()
	var claimed: Dictionary = {}
	for action_id in managed_ids:
		if not actions.has(action_id):
			errors.append("Input bindings are missing action '%s'." % action_id)
			continue
		var events_value: Variant = actions.get(action_id, [])
		if typeof(events_value) != TYPE_ARRAY:
			errors.append("Input bindings for '%s' must be an array." % action_id)
			continue
		var events: Array = events_value
		if events.is_empty() or events.size() > MAX_EVENTS_PER_ACTION:
			errors.append("Input bindings for '%s' must contain between 1 and %d events." % [action_id, MAX_EVENTS_PER_ACTION])
		var keyboard_count := 0
		var gamepad_count := 0
		var local: Dictionary = {}
		for index in range(events.size()):
			var descriptor_errors := validate_descriptor(events[index])
			for message in descriptor_errors:
				errors.append("Input binding '%s' event %d: %s" % [action_id, index, message])
			if not descriptor_errors.is_empty() or typeof(events[index]) != TYPE_DICTIONARY:
				continue
			var descriptor: Dictionary = events[index]
			var signature := descriptor_signature(descriptor)
			if local.has(signature):
				errors.append("Input binding '%s' repeats %s." % [action_id, binding_label(descriptor)])
			else:
				local[signature] = true
			if claimed.has(signature) and str(claimed.get(signature, "")) != action_id:
				errors.append("Input binding %s is assigned to both '%s' and '%s'." % [binding_label(descriptor), claimed.get(signature, ""), action_id])
			else:
				claimed[signature] = action_id
			if descriptor_device(descriptor) == DEVICE_KEYBOARD:
				keyboard_count += 1
			else:
				gamepad_count += 1
		if keyboard_count == 0:
			errors.append("Input binding action '%s' requires a keyboard binding." % action_id)
		if gamepad_count == 0:
			errors.append("Input binding action '%s' requires a controller binding." % action_id)
	for key in actions.keys():
		if not managed_ids.has(str(key)):
			errors.append("Input binding profile contains unknown action '%s'." % key)
	return {"ok": errors.is_empty(), "errors": errors}


static func validate_descriptor(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("event must be an object.")
		return errors
	var descriptor: Dictionary = value
	var type_value: Variant = descriptor.get("type", "")
	if typeof(type_value) != TYPE_STRING:
		errors.append("type must be a string.")
		return errors
	match str(type_value):
		"key":
			var physical: Variant = descriptor.get("physical_keycode", 0)
			if typeof(physical) != TYPE_INT or int(physical) <= 0:
				errors.append("physical_keycode must be a positive integer.")
			for modifier in ["shift", "alt", "ctrl", "meta"]:
				if descriptor.has(modifier) and typeof(descriptor.get(modifier)) != TYPE_BOOL:
					errors.append("%s must be boolean." % modifier)
			if descriptor_has_modifiers(descriptor):
				errors.append(modifier_chord_message())
		"joy_button":
			var button: Variant = descriptor.get("button_index", -1)
			if typeof(button) != TYPE_INT or int(button) < 0 or int(button) > 31:
				errors.append("button_index must be an integer between 0 and 31.")
		"joy_axis":
			var axis: Variant = descriptor.get("axis", -1)
			var direction: Variant = descriptor.get("axis_value", 0.0)
			if typeof(axis) != TYPE_INT or int(axis) < 0 or int(axis) > 15:
				errors.append("axis must be an integer between 0 and 15.")
			if typeof(direction) not in [TYPE_INT, TYPE_FLOAT] or absf(float(direction)) < 0.5 or absf(float(direction)) > 1.0:
				errors.append("axis_value must be between -1 and -0.5 or 0.5 and 1.")
		_:
			errors.append("unsupported event type '%s'." % type_value)
	if errors.is_empty() and descriptor_is_reserved(descriptor):
		errors.append(reserved_descriptor_message(descriptor))
	return errors


static func sanitize_event_list(value: Variant) -> Array:
	var output: Array = []
	if typeof(value) != TYPE_ARRAY:
		return output
	for raw in value:
		var descriptor := sanitize_descriptor(raw)
		if not descriptor.is_empty():
			output.append(descriptor)
	return unique_events(output)


static func descriptor_has_modifiers(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or str((value as Dictionary).get("type", "")) != "key":
		return false
	var descriptor: Dictionary = value
	for modifier in ["shift", "alt", "ctrl", "meta"]:
		if descriptor.has(modifier) and typeof(descriptor.get(modifier)) == TYPE_BOOL and bool(descriptor.get(modifier)):
			return true
	return false


static func sanitize_descriptor(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = value
	match str(source.get("type", "")):
		"key":
			var physical: Variant = source.get("physical_keycode", 0)
			if typeof(physical) != TYPE_INT or int(physical) <= 0 or descriptor_has_modifiers(source):
				return {}
			for modifier in ["shift", "alt", "ctrl", "meta"]:
				if source.has(modifier) and typeof(source.get(modifier)) != TYPE_BOOL:
					return {}
			return key_descriptor(int(physical))
		"joy_button":
			var button: Variant = source.get("button_index", -1)
			return button_descriptor(int(button)) if typeof(button) == TYPE_INT and int(button) >= 0 and int(button) <= 31 else {}
		"joy_axis":
			var axis: Variant = source.get("axis", -1)
			var direction: Variant = source.get("axis_value", 0.0)
			if typeof(axis) != TYPE_INT or int(axis) < 0 or int(axis) > 15 or typeof(direction) not in [TYPE_INT, TYPE_FLOAT] or absf(float(direction)) < 0.5:
				return {}
			return axis_descriptor(int(axis), float(direction))
	return {}


static func key_descriptor(
	physical_keycode: int,
	shift: bool = false,
	alt: bool = false,
	ctrl: bool = false,
	meta: bool = false
) -> Dictionary:
	return {
		"type": "key",
		"physical_keycode": physical_keycode,
		"shift": shift,
		"alt": alt,
		"ctrl": ctrl,
		"meta": meta
	}


static func button_descriptor(button_index: int) -> Dictionary:
	return {"type": "joy_button", "button_index": button_index}


static func axis_descriptor(axis: int, axis_value: float) -> Dictionary:
	return {"type": "joy_axis", "axis": axis, "axis_value": -1.0 if axis_value < 0.0 else 1.0}


static func event_uses_modifiers(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	return key.shift_pressed or key.alt_pressed or key.ctrl_pressed or key.meta_pressed


static func modifier_chord_message() -> String:
	return "Modifier chords are unsupported because gameplay actions use non-exact InputMap matching; press one physical key instead."


static func descriptor_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return {}
		var physical := int(key.physical_keycode)
		if physical <= 0:
			physical = int(key.keycode)
		return key_descriptor(physical, key.shift_pressed, key.alt_pressed, key.ctrl_pressed, key.meta_pressed) if physical > 0 else {}
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button_descriptor(int(button.button_index)) if button.pressed else {}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return axis_descriptor(int(motion.axis), float(motion.axis_value)) if absf(float(motion.axis_value)) >= CAPTURE_AXIS_THRESHOLD else {}
	return {}


static func event_from_descriptor(value: Variant) -> InputEvent:
	var descriptor := sanitize_descriptor(value)
	match str(descriptor.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(descriptor.get("physical_keycode", 0))
			return key
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.device = -1
			button.button_index = int(descriptor.get("button_index", 0))
			return button
		"joy_axis":
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = int(descriptor.get("axis", 0))
			motion.axis_value = float(descriptor.get("axis_value", 1.0))
			return motion
	return null


static func apply_profile(value: Variant) -> Dictionary:
	var validation := validate_profile(value)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "profile": sanitize_profile(value), "errors": validation.get("errors", [])}
	var profile := sanitize_profile(value)
	var actions: Dictionary = profile.get("actions", {})
	for raw in action_definitions():
		var definition: Dictionary = raw
		var action_id := str(definition.get("id", ""))
		var deadzone := float(definition.get("deadzone", 0.2))
		if not InputMap.has_action(action_id):
			InputMap.add_action(action_id, deadzone)
		else:
			InputMap.action_set_deadzone(action_id, deadzone)
		InputMap.action_erase_events(action_id)
		for descriptor in actions.get(action_id, []):
			var event := event_from_descriptor(descriptor)
			if event != null:
				InputMap.action_add_event(action_id, event)
	return {"ok": true, "profile": profile, "errors": []}


static func input_map_matches(value: Variant) -> bool:
	if not bool(validate_profile(value).get("ok", false)):
		return false
	var profile := sanitize_profile(value)
	var actions: Dictionary = profile.get("actions", {})
	for action_id in managed_action_ids():
		if not InputMap.has_action(action_id):
			return false
		if not is_equal_approx(InputMap.action_get_deadzone(action_id), float(action_definition(action_id).get("deadzone", 0.2))):
			return false
		var actual: Array = []
		for event in InputMap.action_get_events(action_id):
			var descriptor := descriptor_from_mapping_event(event)
			if not descriptor.is_empty():
				actual.append(descriptor)
		if signature_array(actions.get(action_id, [])) != signature_array(actual):
			return false
	return true


static func descriptor_from_mapping_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		if event_uses_modifiers(key):
			return {}
		var physical := int(key.physical_keycode)
		if physical <= 0:
			physical = int(key.keycode)
		return key_descriptor(physical) if physical > 0 else {}
	if event is InputEventJoypadButton:
		return button_descriptor(int((event as InputEventJoypadButton).button_index))
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return axis_descriptor(int(motion.axis), float(motion.axis_value))
	return {}


static func rebind(value: Variant, action_id: String, device: String, descriptor_value: Variant) -> Dictionary:
	var original := sanitize_profile(value)
	if not managed_action_ids().has(action_id):
		return {"ok": false, "profile": original, "errors": ["Unknown input action '%s'." % action_id]}
	if device not in [DEVICE_KEYBOARD, DEVICE_GAMEPAD]:
		return {"ok": false, "profile": original, "errors": ["Unknown input device '%s'." % device]}
	if descriptor_has_modifiers(descriptor_value):
		return {"ok": false, "profile": original, "errors": [modifier_chord_message()]}
	var descriptor := sanitize_descriptor(descriptor_value)
	if descriptor.is_empty() or descriptor_device(descriptor) != device:
		return {"ok": false, "profile": original, "errors": ["Unsupported input event for the selected device."]}
	if descriptor_is_reserved(descriptor):
		return {"ok": false, "profile": original, "errors": [reserved_descriptor_message(descriptor)]}
	var actions: Dictionary = (original.get("actions", {}) as Dictionary).duplicate(true)
	var target_events: Array = actions.get(action_id, [])
	var target_device_events := events_for_device(target_events, device)
	var signature := descriptor_signature(descriptor)
	for current in target_device_events:
		if descriptor_signature(current) == signature:
			return {"ok": true, "profile": original, "swapped_with": "", "changed": false, "errors": []}
	var conflict_action := ""
	for other_action in managed_action_ids():
		if other_action == action_id:
			continue
		for other in actions.get(other_action, []):
			if descriptor_signature(other) == signature:
				conflict_action = other_action
				break
		if not conflict_action.is_empty():
			break
	actions[action_id] = replace_device_events(target_events, device, [descriptor])
	if not conflict_action.is_empty():
		actions[conflict_action] = replace_device_events(actions.get(conflict_action, []), device, target_device_events)
	var profile := {"schema_version": PROFILE_SCHEMA, "actions": actions}
	var validation := validate_profile(profile)
	return {"ok": true, "profile": profile, "swapped_with": conflict_action, "changed": true, "errors": []} if bool(validation.get("ok", false)) else {"ok": false, "profile": original, "errors": validation.get("errors", [])}


static func replace_device_events(value: Variant, device: String, replacements: Array) -> Array:
	var output: Array = []
	if typeof(value) == TYPE_ARRAY:
		for raw in value:
			if typeof(raw) == TYPE_DICTIONARY and descriptor_device(raw) != device:
				output.append((raw as Dictionary).duplicate(true))
	for replacement in replacements:
		if typeof(replacement) == TYPE_DICTIONARY:
			output.append((replacement as Dictionary).duplicate(true))
	return unique_events(output)


static func events_for_device(value: Variant, device: String) -> Array:
	var output: Array = []
	if typeof(value) == TYPE_ARRAY:
		for raw in value:
			if typeof(raw) == TYPE_DICTIONARY and descriptor_device(raw) == device:
				output.append((raw as Dictionary).duplicate(true))
	return output


static func action_events(value: Variant, action_id: String) -> Array:
	var actions: Dictionary = sanitize_profile(value).get("actions", {})
	var events: Variant = actions.get(action_id, [])
	return (events as Array).duplicate(true) if typeof(events) == TYPE_ARRAY else []


static func rows(value: Variant, device: String) -> Array:
	var profile := sanitize_profile(value)
	var actions: Dictionary = profile.get("actions", {})
	var output: Array = []
	for raw in action_definitions():
		var definition: Dictionary = raw
		var action_id := str(definition.get("id", ""))
		output.append({
			"id": action_id,
			"label": str(definition.get("label", action_id)).to_upper(),
			"kind": "binding",
			"value": device_binding_text_from_events(actions.get(action_id, []), device)
		})
	return output


static func action_hint(value: Variant, action_id: String) -> String:
	return action_hint_from_events(action_events(value, action_id))


static func action_hint_from_events(value: Variant) -> String:
	var labels := PackedStringArray()
	var keyboard := events_for_device(value, DEVICE_KEYBOARD)
	var gamepad := events_for_device(value, DEVICE_GAMEPAD)
	if not keyboard.is_empty():
		labels.append(binding_label(keyboard[0]))
	if not gamepad.is_empty():
		labels.append(binding_label(gamepad[0]))
	return " / ".join(labels)


static func device_binding_text(value: Variant, action_id: String, device: String) -> String:
	return device_binding_text_from_events(action_events(value, action_id), device)


static func device_binding_text_from_events(value: Variant, device: String) -> String:
	var descriptors := events_for_device(value, device)
	var labels := PackedStringArray()
	for index in range(mini(2, descriptors.size())):
		labels.append(binding_label(descriptors[index]))
	if descriptors.size() > 2:
		labels.append("+%d" % (descriptors.size() - 2))
	return " / ".join(labels) if not labels.is_empty() else "UNBOUND"


static func binding_label(value: Variant) -> String:
	var descriptor := sanitize_descriptor(value)
	match str(descriptor.get("type", "")):
		"key": return physical_key_label(int(descriptor.get("physical_keycode", 0)))
		"joy_button": return joy_button_label(int(descriptor.get("button_index", 0)))
		"joy_axis": return joy_axis_label(int(descriptor.get("axis", 0)), float(descriptor.get("axis_value", 1.0)))
	return "UNBOUND"


static func physical_key_label(physical_keycode: int) -> String:
	if physical_keycode >= 48 and physical_keycode <= 57 or physical_keycode >= 65 and physical_keycode <= 90:
		return String.chr(physical_keycode)
	match physical_keycode:
		32: return "SPACE"
		4194305: return "ESC"
		4194311: return "LEFT"
		4194313: return "RIGHT"
		4194320: return "UP"
		4194322: return "DOWN"
	var keycode := DisplayServer.keyboard_get_keycode_from_physical(physical_keycode)
	var label := OS.get_keycode_string(keycode)
	return label.to_upper() if not label.is_empty() else "KEY %d" % physical_keycode


static func joy_button_label(button_index: int) -> String:
	var labels := ["A", "B", "X", "Y", "BACK", "GUIDE", "START", "L3", "R3", "LB", "RB", "D-PAD UP", "D-PAD DOWN", "D-PAD LEFT", "D-PAD RIGHT"]
	return labels[button_index] if button_index >= 0 and button_index < labels.size() else "BUTTON %d" % button_index


static func joy_axis_label(axis: int, axis_value: float) -> String:
	var positive := axis_value >= 0.0
	match axis:
		0: return "LS RIGHT" if positive else "LS LEFT"
		1: return "LS DOWN" if positive else "LS UP"
		2: return "RS RIGHT" if positive else "RS LEFT"
		3: return "RS DOWN" if positive else "RS UP"
		4: return "LT" if positive else "AXIS 4-"
		5: return "RT" if positive else "AXIS 5-"
	return "AXIS %d%s" % [axis, "+" if positive else "-"]


static func descriptor_device(value: Variant) -> String:
	return DEVICE_KEYBOARD if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("type", "")) == "key" else DEVICE_GAMEPAD


static func descriptor_signature(value: Variant) -> String:
	var descriptor := sanitize_descriptor(value)
	match str(descriptor.get("type", "")):
		"key": return "key:%d" % int(descriptor.get("physical_keycode", 0))
		"joy_button": return "button:%d" % int(descriptor.get("button_index", -1))
		"joy_axis": return "axis:%d:%d" % [int(descriptor.get("axis", -1)), 1 if float(descriptor.get("axis_value", 1.0)) >= 0.0 else -1]
	return ""


static func signature_array(value: Variant) -> PackedStringArray:
	var output := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for raw in value:
			var signature := descriptor_signature(raw)
			if not signature.is_empty():
				output.append(signature)
	output.sort()
	return output


static func unique_events(value: Variant) -> Array:
	var output: Array = []
	var signatures: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		return output
	for raw in value:
		var descriptor := sanitize_descriptor(raw)
		var signature := descriptor_signature(descriptor)
		if descriptor.is_empty() or signature.is_empty() or signatures.has(signature):
			continue
		signatures[signature] = true
		output.append(descriptor)
	return output


static func descriptor_is_reserved(value: Variant) -> bool:
	if descriptor_has_modifiers(value):
		return true
	var descriptor := sanitize_descriptor(value)
	if str(descriptor.get("type", "")) == "key":
		return int(descriptor.get("physical_keycode", 0)) in [RESERVED_ESCAPE_PHYSICAL, RESERVED_OPTIONS_PHYSICAL]
	return str(descriptor.get("type", "")) == "joy_button" and int(descriptor.get("button_index", -1)) == RESERVED_START_BUTTON


static func reserved_descriptor_message(value: Variant) -> String:
	if descriptor_has_modifiers(value):
		return modifier_chord_message()
	var descriptor := sanitize_descriptor(value)
	if str(descriptor.get("type", "")) == "key" and int(descriptor.get("physical_keycode", 0)) == RESERVED_ESCAPE_PHYSICAL:
		return "Escape is reserved for cancel and Pause recovery."
	if str(descriptor.get("type", "")) == "key" and int(descriptor.get("physical_keycode", 0)) == RESERVED_OPTIONS_PHYSICAL:
		return "O is reserved for direct Options recovery."
	if str(descriptor.get("type", "")) == "joy_button" and int(descriptor.get("button_index", -1)) == RESERVED_START_BUTTON:
		return "Start is reserved for Pause and menu recovery."
	return "That input is reserved for menu recovery."
