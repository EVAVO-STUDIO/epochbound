extends SceneTree

const CompleteValidator = preload("res://src/content/complete_content_validator.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var validation := CompleteValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass complete multiplayer-aware validation.")
	check(int(validation.get("multiplayer_area_count", 0)) == 4, "Reference campaign must expose four authored online areas.")
	check(int(validation.get("pvp_area_count", 0)) == 1, "Reference campaign must expose one intentional invasion area.")

	var runtime := await instantiate_runtime()
	if runtime == null:
		finish()
		return
	var session := runtime.get_node_or_null("MultiplayerSession")
	var post_tick := runtime.get_node_or_null("MultiplayerPostTick")
	var save_guard := runtime.get_node_or_null("MultiplayerSaveGuard")
	var multiplayer_overlay := runtime.get_node_or_null("PresentationLayer/MultiplayerOverlay")
	check(session != null, "Playable scene must include MultiplayerSession.")
	check(post_tick != null, "Playable scene must include MultiplayerPostTick.")
	check(save_guard != null, "Playable scene must include MultiplayerSaveGuard.")
	check(multiplayer_overlay != null, "Playable scene must include MultiplayerOverlay.")
	if session == null:
		cleanup(runtime)
		finish()
		return
	check(bool(session.call("multiplayer_runtime_contract_ok")), "Multiplayer runtime must preserve host-only progression and session-only PvP rewards.")
	check(multiplayer_overlay != null and bool(multiplayer_overlay.call("multiplayer_overlay_contract_ok")), "Multiplayer overlay must retain lobby, peer and area presentation contracts.")

	runtime.call("change_flow", 4)
	check(bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)), "Runtime must enter Clockwood Edge for online testing.")
	runtime.set("player", Vector2(360, 240))
	runtime.set("facing", Vector2.RIGHT)
	runtime.set("companion", Vector2(344, 264))
	check(bool(session.call("configure_test_host_session")), "Test host must initialise without opening a socket.")
	check(str((session.call("online_area") as Dictionary).get("id", "")) == "clockwood_ashen_hunt", "Host inside the Ashen hunt bounds must resolve the authored PvP area.")

	var ally_result: Dictionary = session.call("register_test_peer", 2, MultiplayerSessionModel.ROLE_ALLY)
	var invader_result: Dictionary = session.call("register_test_peer", 3, MultiplayerSessionModel.ROLE_INVADER)
	check(bool(ally_result.get("ok", false)), "One co-op ally must join the host-authoritative session.")
	check(bool(invader_result.get("ok", false)), "One invader must join while the host is inside the authored PvP area.")
	check(bool(session.call("blocks_manual_save")), "Manual saves must be blocked while remote peers are present.")
	check(bool(session.call("blocks_autosave")), "Autosave flushes must defer while an invader is present.")

	var peers: Dictionary = session.get("peers")
	var ally: Dictionary = peers.get(2, {})
	ally["position"] = Vector2(300, 232)
	ally["facing"] = Vector2.RIGHT
	ally["pvp_grace"] = 0.0
	peers[2] = ally
	var invader: Dictionary = peers.get(3, {})
	invader["position"] = Vector2(392, 240)
	invader["facing"] = Vector2.LEFT
	invader["pvp_grace"] = 0.0
	peers[3] = invader
	session.set("peers", peers)

	var entities: Array = runtime.get("runtime_entities")
	var hound_index := entity_index(entities, "clockwood_hound_west")
	check(hound_index >= 0, "Clockwood West Hound must resolve for co-op combat.")
	var hound_health_before := int((entities[hound_index] as Dictionary).get("health", 0)) if hound_index >= 0 else 0
	check(bool((session.call("accept_test_input", 2, 1, {"direction": Vector2.ZERO, "attack": true}) as Dictionary).get("ok", false)), "Fresh ally combat input must reach the host authority.")
	session.call("post_runtime_process", 0.016)
	entities = runtime.get("runtime_entities")
	if hound_index >= 0:
		check(int((entities[hound_index] as Dictionary).get("health", 0)) == hound_health_before - MultiplayerSessionModel.ATTACK_DAMAGE, "Co-op ally attacks must damage host-owned enemies exactly once.")

	var host_health_before := int(runtime.get("player_health"))
	check(bool((session.call("accept_test_input", 3, 1, {"direction": Vector2.ZERO, "attack": true}) as Dictionary).get("ok", false)), "Fresh invader combat input must reach the host authority.")
	session.call("post_runtime_process", 0.016)
	check(int(runtime.get("player_health")) < host_health_before, "Invader attacks inside the authored PvP area must damage the host.")

	peers = session.get("peers")
	invader = peers.get(3, {})
	invader["hurt_lock"] = 0.0
	invader["position"] = Vector2(392, 240)
	invader["pvp_grace"] = 0.0
	peers[3] = invader
	session.set("peers", peers)
	runtime.set("player", Vector2(360, 240))
	runtime.set("facing", Vector2.RIGHT)
	session.call("sync_host_peer")
	var invader_health_before := int(invader.get("health", 0))
	check(bool(session.call("try_host_attack_invader")), "Host melee must prioritize a valid invader in the authored PvP area.")
	peers = session.get("peers")
	check(int((peers.get(3, {}) as Dictionary).get("health", 0)) == invader_health_before - MultiplayerSessionModel.ATTACK_DAMAGE, "Host-authoritative PvP damage must apply once to the invader.")

	var profile: Dictionary = runtime.call("capture_save_profile", "slot_1", "Online isolation smoke")
	var payload: Dictionary = profile.get("payload", {})
	check(not payload.has("multiplayer_peers") and not payload.has("peer_roles") and not payload.has("invasion_state"), "Durable profiles must exclude online peer and invasion state.")
	var invalid_profile := profile.duplicate(true)
	var invalid_payload: Dictionary = (invalid_profile.get("payload", {}) as Dictionary).duplicate(true)
	invalid_payload["multiplayer_peers"] = {2: {"role": "ally"}}
	invalid_profile["payload"] = invalid_payload
	var invalid_validation := CompleteValidator.validate_profile(invalid_profile, CAMPAIGN_PATH)
	check(not bool(invalid_validation.get("ok", true)), "Complete profile validation must reject injected ephemeral multiplayer state.")

	var snapshot: Dictionary = session.call("build_world_snapshot")
	check(int(snapshot.get("protocol_version", 0)) == 1, "Host snapshots must declare a bounded protocol version.")
	check((snapshot.get("peers", []) as Array).size() == 3, "Host snapshot must include host, ally and invader transient actors.")
	check(not snapshot.has("inventory") and not snapshot.has("session_state") and not snapshot.has("quest_progress"), "Network snapshots must not replicate durable inventory or story state.")

	var client_runtime := await instantiate_runtime()
	if client_runtime != null:
		var client_session := client_runtime.get_node_or_null("MultiplayerSession")
		check(client_session != null, "Client runtime must include MultiplayerSession.")
		if client_session != null:
			client_session.set("mode", MultiplayerSessionModel.MODE_CLIENT)
			client_session.set("local_role", MultiplayerSessionModel.ROLE_ALLY)
			client_session.set("local_peer_id", 2)
			check(bool(client_session.call("load_campaign_multiplayer_contract")), "Client must load the same authored multiplayer contract.")
			check(bool(client_session.call("apply_world_snapshot", snapshot)), "Client must apply a fresh authoritative world snapshot.")
			check(str((client_runtime.get("map_data") as Dictionary).get("id", "")) == "clockwood_edge", "Client snapshot must restore the host map.")
			check(str(client_runtime.get("current_era_id")) == "ashen", "Client snapshot must restore the host era.")
			check((client_runtime.get("player") as Vector2).is_equal_approx((client_session.get("peers") as Dictionary).get(2, {}).get("position", Vector2.ZERO)), "Client camera actor must follow the local predicted peer.")
			check(not bool(client_session.call("apply_world_snapshot", snapshot)), "Repeated snapshot sequences must be rejected as stale.")
		cleanup(client_runtime)

	cleanup(runtime)
	finish()


func instantiate_runtime() -> Node:
	var packed := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Multiplayer runtime scene must load.")
	if not packed is PackedScene:
		return null
	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Multiplayer runtime scene must instantiate.")
	if runtime == null:
		return null
	root.add_child(runtime)
	await process_frame
	return runtime


func entity_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if typeof(entities[index]) == TYPE_DICTIONARY and str((entities[index] as Dictionary).get("placement_id", "")) == placement_id:
			return index
	return -1


func cleanup(runtime: Node) -> void:
	if runtime == null:
		return
	root.remove_child(runtime)
	runtime.free()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Multiplayer runtime smoke test passed: authored online areas, co-op enemy damage, invasion PvP, save isolation and authoritative snapshot restoration are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
