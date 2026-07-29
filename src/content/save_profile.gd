extends RefCounted

const CURRENT_SCHEMA := 1
const AUTOSAVE_SLOT := "autosave"
const MIN_MANUAL_SLOTS := 1
const MAX_MANUAL_SLOTS := 9
const ALLOWED_COMPANION_COMMANDS := ["follow", "stay", "guard"]


static func default_policy() -> Dictionary:
	return {
		"manual_slots": 3,
		"autosave_enabled": true,
		"autosave_on_travel": true,
		"autosave_on_progress": true,
		"allow_manual_save_in_combat": false
	}


static func policy(campaign: Dictionary) -> Dictionary:
	var output := default_policy()
	var value: Variant = campaign.get("save_policy", {})
	if typeof(value) == TYPE_DICTIONARY:
		for key in output.keys():
			if (value as Dictionary).has(key):
				output[key] = (value as Dictionary).get(key)
	output["manual_slots"] = clampi(
		int(output.get("manual_slots", 3)),
		MIN_MANUAL_SLOTS,
		MAX_MANUAL_SLOTS
	)
	return output


static func manual_slot_ids(campaign: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var count := int(policy(campaign).get("manual_slots", 3))
	for index in range(1, count + 1):
		output.append("slot_%d" % index)
	return output


static func all_slot_ids(campaign: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	if bool(policy(campaign).get("autosave_enabled", true)):
		output.append(AUTOSAVE_SLOT)
	for slot_id in manual_slot_ids(campaign):
		output.append(slot_id)
	return output


static func valid_slot_id(slot_id: String) -> bool:
	if slot_id == AUTOSAVE_SLOT:
		return true
	if not slot_id.begins_with("slot_"):
		return false
	var suffix := slot_id.trim_prefix("slot_")
	return suffix.is_valid_int() and int(suffix) >= 1 and int(suffix) <= MAX_MANUAL_SLOTS


static func slot_label(slot_id: String) -> String:
	if slot_id == AUTOSAVE_SLOT:
		return "AUTOSAVE"
	if valid_slot_id(slot_id):
		return "SLOT %d" % int(slot_id.trim_prefix("slot_"))
	return slot_id.replace("_", " ").to_upper()


static func build_profile(
	campaign_id: String,
	slot_id: String,
	metadata: Dictionary,
	payload: Dictionary
) -> Dictionary:
	var profile := {
		"schema_version": CURRENT_SCHEMA,
		"profile_id": "%s:%s" % [campaign_id, slot_id],
		"campaign_id": campaign_id,
		"slot_id": slot_id,
		"metadata": canonicalize(metadata),
		"payload": canonicalize(payload)
	}
	refresh_checksum(profile)
	return profile


static func migrate(raw_profile: Dictionary) -> Dictionary:
	var version := int(raw_profile.get("schema_version", 0))
	if version == CURRENT_SCHEMA:
		return {
			"ok": true,
			"profile": raw_profile.duplicate(true),
			"migrated": false,
			"from_version": CURRENT_SCHEMA,
			"errors": []
		}
	if version > CURRENT_SCHEMA:
		return {
			"ok": false,
			"profile": {},
			"migrated": false,
			"from_version": version,
			"errors": ["Save profile schema %d is newer than supported schema %d." % [version, CURRENT_SCHEMA]]
		}
	if version < 0:
		return {
			"ok": false,
			"profile": {},
			"migrated": false,
			"from_version": version,
			"errors": ["Save profile schema_version cannot be negative."]
		}

	# Legacy schema 0 stored the durable state directly on the root object.
	var campaign_id := str(raw_profile.get("campaign_id", "")).strip_edges()
	var slot_id := str(raw_profile.get("slot_id", raw_profile.get("slot", "slot_1"))).strip_edges()
	var legacy_metadata_value: Variant = raw_profile.get("metadata", {})
	var metadata: Dictionary = legacy_metadata_value.duplicate(true) if typeof(legacy_metadata_value) == TYPE_DICTIONARY else {}
	metadata["saved_at_unix"] = int(metadata.get("saved_at_unix", raw_profile.get("saved_at_unix", 0)))
	metadata["play_time_seconds"] = float(metadata.get("play_time_seconds", raw_profile.get("play_time_seconds", 0.0)))
	metadata["reason"] = str(metadata.get("reason", "Migrated legacy save"))
	metadata["map_id"] = str(metadata.get("map_id", raw_profile.get("map_id", raw_profile.get("map", ""))))
	metadata["era_id"] = str(metadata.get("era_id", raw_profile.get("era_id", raw_profile.get("era", ""))))

	var legacy_payload_value: Variant = raw_profile.get("payload", {})
	var payload: Dictionary = legacy_payload_value.duplicate(true) if typeof(legacy_payload_value) == TYPE_DICTIONARY else {}
	if payload.is_empty():
		payload = {
			"map_id": str(raw_profile.get("map_id", raw_profile.get("map", ""))),
			"era_id": str(raw_profile.get("era_id", raw_profile.get("era", ""))),
			"player_position": normalise_position(raw_profile.get("player_position", raw_profile.get("player", {}))),
			"companion_position": normalise_position(raw_profile.get("companion_position", raw_profile.get("companion", {}))),
			"facing": normalise_position(raw_profile.get("facing", {"x": 0, "y": 1})),
			"player_health": int(raw_profile.get("player_health", raw_profile.get("health", 1))),
			"companion_health": int(raw_profile.get("companion_health", 1)),
			"clock_shards": int(raw_profile.get("clock_shards", 0)),
			"inventory": dictionary_or_empty(raw_profile.get("inventory", {})),
			"unlocked_recipes": string_array(raw_profile.get("unlocked_recipes", raw_profile.get("recipes", []))),
			"session_state": dictionary_or_empty(raw_profile.get("session_state", raw_profile.get("state", {}))),
			"quest_progress": dictionary_or_empty(raw_profile.get("quest_progress", raw_profile.get("quests", {}))),
			"companion_command": "follow",
			"companion_hold_position": normalise_position(raw_profile.get("companion_position", raw_profile.get("companion", {})))
		}
	var migrated := build_profile(campaign_id, slot_id, metadata, payload)
	return {
		"ok": true,
		"profile": migrated,
		"migrated": true,
		"from_version": version,
		"errors": []
	}


static func refresh_checksum(profile: Dictionary) -> String:
	profile["checksum"] = checksum_for(profile)
	return str(profile.get("checksum", ""))


static func checksum_for(profile: Dictionary) -> String:
	var unsigned := profile.duplicate(true)
	unsigned.erase("checksum")
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	context.update(canonical_json(unsigned).to_utf8_buffer())
	return context.finish().hex_encode()


static func checksum_valid(profile: Dictionary) -> bool:
	var authored := str(profile.get("checksum", "")).strip_edges()
	return not authored.is_empty() and authored == checksum_for(profile)


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(canonicalize(value), "", true)


static func canonicalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys: Array[String] = []
			for key in source.keys():
				keys.append(str(key))
			keys.sort()
			var output: Dictionary = {}
			for key in keys:
				output[key] = canonicalize(source.get(key))
			return output
		TYPE_ARRAY:
			var output: Array = []
			for item in value:
				output.append(canonicalize(item))
			return output
		TYPE_PACKED_STRING_ARRAY:
			var output: Array = []
			for item in value:
				output.append(str(item))
			return output
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var output: Array = []
			for item in value:
				output.append(item)
			return output
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return {"x": snappedf(vector.x, 0.001), "y": snappedf(vector.y, 0.001)}
		TYPE_VECTOR2I:
			var vector: Vector2i = value
			return {"x": vector.x, "y": vector.y}
		_:
			return value


static func validate_structure(profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(profile.get("schema_version", -1)) != CURRENT_SCHEMA:
		errors.append("Save profile uses unsupported schema_version.")
	var campaign_id := str(profile.get("campaign_id", "")).strip_edges()
	if campaign_id.is_empty():
		errors.append("Save profile campaign_id is required.")
	var slot_id := str(profile.get("slot_id", "")).strip_edges()
	if not valid_slot_id(slot_id):
		errors.append("Save profile slot_id '%s' is invalid." % slot_id)
	if str(profile.get("profile_id", "")) != "%s:%s" % [campaign_id, slot_id]:
		errors.append("Save profile profile_id does not match its campaign and slot.")
	if typeof(profile.get("metadata")) != TYPE_DICTIONARY:
		errors.append("Save profile metadata must be an object.")
	else:
		var metadata: Dictionary = profile.get("metadata", {})
		if int(metadata.get("saved_at_unix", -1)) < 0:
			errors.append("Save metadata saved_at_unix cannot be negative.")
		if float(metadata.get("play_time_seconds", -1.0)) < 0.0:
			errors.append("Save metadata play_time_seconds cannot be negative.")
	if typeof(profile.get("payload")) != TYPE_DICTIONARY:
		errors.append("Save profile payload must be an object.")
	else:
		validate_payload(profile.get("payload", {}), errors)
	if not checksum_valid(profile):
		errors.append("Save profile checksum is missing or does not match the durable state.")
	return {"ok": errors.is_empty(), "errors": errors}


static func validate_payload(payload: Dictionary, errors: Array[String]) -> void:
	for field in ["map_id", "era_id"]:
		if str(payload.get(field, "")).strip_edges().is_empty():
			errors.append("Save payload %s is required." % field)
	for field in ["player_position", "companion_position", "facing", "companion_hold_position"]:
		if not valid_position(payload.get(field)):
			errors.append("Save payload %s must contain numeric x and y values." % field)
	for field in ["player_health", "companion_health"]:
		if int(payload.get(field, 0)) <= 0:
			errors.append("Save payload %s must be positive." % field)
	if int(payload.get("clock_shards", -1)) < 0:
		errors.append("Save payload clock_shards cannot be negative.")
	for field in ["inventory", "session_state", "quest_progress"]:
		if typeof(payload.get(field)) != TYPE_DICTIONARY:
			errors.append("Save payload %s must be an object." % field)
	if typeof(payload.get("unlocked_recipes")) != TYPE_ARRAY:
		errors.append("Save payload unlocked_recipes must be an array.")
	var command := str(payload.get("companion_command", "follow"))
	if not ALLOWED_COMPANION_COMMANDS.has(command):
		errors.append("Save payload companion_command '%s' is unsupported." % command)
	if not is_json_safe(payload):
		errors.append("Save payload contains a value that cannot be represented safely in JSON.")


static func profile_summary(profile: Dictionary) -> Dictionary:
	var metadata_value: Variant = profile.get("metadata", {})
	var metadata: Dictionary = metadata_value if typeof(metadata_value) == TYPE_DICTIONARY else {}
	var payload_value: Variant = profile.get("payload", {})
	var payload: Dictionary = payload_value if typeof(payload_value) == TYPE_DICTIONARY else {}
	var inventory_value: Variant = payload.get("inventory", {})
	var inventory: Dictionary = inventory_value if typeof(inventory_value) == TYPE_DICTIONARY else {}
	var quests_value: Variant = payload.get("quest_progress", {})
	var quests: Dictionary = quests_value if typeof(quests_value) == TYPE_DICTIONARY else {}
	var active_quests := 0
	var completed_quests := 0
	for value in quests.values():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var status := str((value as Dictionary).get("status", "inactive"))
		if status == "active":
			active_quests += 1
		elif status == "completed":
			completed_quests += 1
	return {
		"slot_id": str(profile.get("slot_id", "")),
		"slot_label": slot_label(str(profile.get("slot_id", ""))),
		"campaign_id": str(profile.get("campaign_id", "")),
		"saved_at_unix": int(metadata.get("saved_at_unix", 0)),
		"play_time_seconds": float(metadata.get("play_time_seconds", 0.0)),
		"reason": str(metadata.get("reason", "")),
		"map_id": str(payload.get("map_id", metadata.get("map_id", ""))),
		"era_id": str(payload.get("era_id", metadata.get("era_id", ""))),
		"player_health": int(payload.get("player_health", 0)),
		"companion_health": int(payload.get("companion_health", 0)),
		"clock_shards": int(payload.get("clock_shards", 0)),
		"inventory_stacks": inventory.size(),
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"state_keys": (payload.get("session_state", {}) as Dictionary).size() if typeof(payload.get("session_state")) == TYPE_DICTIONARY else 0
	}


static func normalise_position(value: Variant) -> Dictionary:
	if value is Vector2:
		return canonicalize(value)
	if value is Vector2i:
		return canonicalize(value)
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return {"x": float(data.get("x", 0.0)), "y": float(data.get("y", 0.0))}
	return {"x": 0.0, "y": 0.0}


static func valid_position(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = value
	return data.has("x") and data.has("y") and typeof(data.get("x")) in [TYPE_INT, TYPE_FLOAT] and typeof(data.get("y")) in [TYPE_INT, TYPE_FLOAT]


static func dictionary_or_empty(value: Variant) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


static func string_array(value: Variant) -> Array:
	var output: Array = []
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			if bool((value as Dictionary).get(key, false)):
				output.append(str(key))
	elif typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty() and not output.has(text):
				output.append(text)
	output.sort()
	return output


static func is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			for item in value:
				if not is_json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				if typeof(key) != TYPE_STRING or not is_json_safe((value as Dictionary).get(key)):
					return false
			return true
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return true
		_:
			return false
