@tool
extends RefCounted

const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const CURRENT_SCHEMA := 1
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 27491
const MIN_PORT := 1024
const MAX_PORT := 65535
const MAX_ADDRESS_LENGTH := 253
const ALLOWED_ADDRESS_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:[]%"


static func default_profile(
	default_port: int = DEFAULT_PORT,
	default_name: String = "WANDERER"
) -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA,
		"address": DEFAULT_ADDRESS,
		"port": clampi(default_port, MIN_PORT, MAX_PORT),
		"player_name": MultiplayerSessionModel.sanitize_name(default_name, "WANDERER")
	}


static func sanitize_address(value: Variant, fallback: String = DEFAULT_ADDRESS) -> String:
	var candidate := str(value).strip_edges()
	if (
		candidate.begins_with("[")
		and candidate.ends_with("]")
		and candidate.count(":") >= 2
	):
		candidate = candidate.substr(1, candidate.length() - 2)
	if candidate.length() > MAX_ADDRESS_LENGTH:
		candidate = candidate.left(MAX_ADDRESS_LENGTH)
	return candidate if address_is_valid(candidate) else fallback


static func address_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var candidate := str(value).strip_edges()
	if candidate.is_empty() or candidate.length() > MAX_ADDRESS_LENGTH:
		return false
	if candidate.contains("://") or candidate.contains("/") or candidate.contains("\\"):
		return false
	if candidate.contains("[") or candidate.contains("]"):
		if (
			not candidate.begins_with("[")
			or not candidate.ends_with("]")
			or candidate.count(":") < 2
		):
			return false
		candidate = candidate.substr(1, candidate.length() - 2)
	if candidate.contains(":") and candidate.count(":") < 2:
		return false
	if candidate.begins_with(".") or candidate.ends_with(".") or candidate.contains(".."):
		return false
	var has_alphanumeric := false
	for index in range(candidate.length()):
		var character := candidate.substr(index, 1)
		if not ALLOWED_ADDRESS_CHARACTERS.contains(character):
			return false
		if (
			character >= "A" and character <= "Z"
			or character >= "a" and character <= "z"
			or character >= "0" and character <= "9"
		):
			has_alphanumeric = true
	return has_alphanumeric


static func port_is_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= MIN_PORT and int(value) <= MAX_PORT


static func player_name_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var raw := str(value).strip_edges()
	if raw.is_empty():
		return false
	return MultiplayerSessionModel.sanitize_name(raw, "") == raw


static func sanitize(
	value: Variant,
	default_port: int = DEFAULT_PORT,
	default_name: String = "WANDERER"
) -> Dictionary:
	var output := default_profile(default_port, default_name)
	if typeof(value) != TYPE_DICTIONARY:
		return output
	var source: Dictionary = value
	output["address"] = sanitize_address(source.get("address", output["address"]))
	var port_value: Variant = source.get("port", output["port"])
	if typeof(port_value) == TYPE_INT:
		output["port"] = clampi(int(port_value), MIN_PORT, MAX_PORT)
	output["player_name"] = MultiplayerSessionModel.sanitize_name(
		source.get("player_name", output["player_name"]),
		str(output["player_name"])
	)
	output["schema_version"] = CURRENT_SCHEMA
	return output


static func validate(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Multiplayer connection profile root must be an object."]}
	var source: Dictionary = value
	var schema_value: Variant = source.get("schema_version", 0)
	if typeof(schema_value) != TYPE_INT:
		errors.append("Multiplayer connection profile schema_version must be an integer.")
	elif int(schema_value) < 0 or int(schema_value) > CURRENT_SCHEMA:
		errors.append("Multiplayer connection profile schema %d is unsupported." % int(schema_value))
	if source.has("address") and not address_is_valid(source.get("address")):
		errors.append("Connection address must be a hostname or IPv4/IPv6 address without a URL scheme or path.")
	if source.has("port") and not port_is_valid(source.get("port")):
		errors.append("Connection UDP port must be an integer between %d and %d." % [MIN_PORT, MAX_PORT])
	if source.has("player_name") and not player_name_is_valid(source.get("player_name")):
		errors.append("Online player name may use only letters, numbers, spaces, underscores and hyphens.")
	return {"ok": errors.is_empty(), "errors": errors}


static func migrate(
	value: Variant,
	default_port: int = DEFAULT_PORT,
	default_name: String = "WANDERER"
) -> Dictionary:
	var validation := validate(value)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"profile": {},
			"migrated": false,
			"from_version": -1,
			"errors": validation.get("errors", [])
		}
	var source: Dictionary = value
	var from_version := int(source.get("schema_version", 0))
	var migrated := from_version != CURRENT_SCHEMA
	for required_key in ["address", "port", "player_name"]:
		if not source.has(required_key):
			migrated = true
	return {
		"ok": true,
		"profile": sanitize(source, default_port, default_name),
		"migrated": migrated,
		"from_version": from_version,
		"errors": []
	}


static func summary(profile: Dictionary) -> String:
	var sanitized := sanitize(profile)
	return "%s:%d  •  %s" % [
		sanitized.get("address", DEFAULT_ADDRESS),
		int(sanitized.get("port", DEFAULT_PORT)),
		str(sanitized.get("player_name", "WANDERER")).to_upper()
	]
