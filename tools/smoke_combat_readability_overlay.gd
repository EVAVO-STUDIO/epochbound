extends SceneTree

const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Combat-readable runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	root.add_child(runtime)
	await process_frame
	var root_script: Variant = runtime.get_script()
	check(root_script is GDScript, "Runtime root must retain its presentation-safe adapter.")
	if root_script is GDScript:
		check(str((root_script as GDScript).resource_path) == "res://src/presentation_runtime_current.gd", "Playable scene must bind the presentation-safe runtime adapter.")
	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(overlay != null, "Playable scene must include the combat readability overlay.")
	if overlay == null:
		root.remove_child(runtime)
		runtime.free()
		finish()
		return
	check(str(overlay.get_script().resource_path) == "res://src/combat_readability_overlay.gd", "Playable scene must bind the combat readability overlay.")
	check(bool(overlay.call("combat_readability_contract_ok")), "Combat readability must preserve environment, animation and presentation contracts.")
	check(bool(runtime.call("presentation_overlay_handles_combat_readability")), "Runtime must suppress duplicate base-layer combat rendering when the overlay is active.")

	runtime.set("flow", 4)
	runtime.set("player", Vector2(100, 200))
	runtime.set("companion", Vector2(100, 180))
	runtime.set("runtime_entities", [{
		"placement_id": "depth_prop",
		"position": Vector2(100, 220),
		"active": true,
		"definition": {"kind": "prop", "appearance": {"shape": "crate"}}
	}])
	runtime.set("projectiles", [{
		"source_kind": "player",
		"source_id": "test_weapon",
		"previous_position": Vector2(70, 210),
		"position": Vector2(100, 210),
		"radius": 3.0,
		"color": Color("e7c56c"),
		"active": true
	}])
	check(int(overlay.call("combat_projectile_count")) == 1, "One active projectile must be promoted into the presentation layer.")
	var order: PackedStringArray = overlay.call("combat_depth_order_keys")
	check(order.size() == 4, "Combat depth ordering must include player, companion, entity and projectile.")
	if order.size() == 4:
		check(order[0] == "companion", "The shallowest ground contact must render first.")
		check(order[1] == "player", "Player depth must remain stable around projectiles.")
		check(order[2].begins_with("projectile:"), "Projectile depth must resolve from its world-space position.")
		check(order[3] == "entity:depth_prop", "The deepest entity must render in front.")
	var segment: Dictionary = overlay.call("projectile_screen_segment", (runtime.get("projectiles") as Array)[0])
	var start_value: Variant = segment.get("start", Vector2.ZERO)
	var finish_value: Variant = segment.get("finish", Vector2.ZERO)
	var start: Vector2 = start_value if start_value is Vector2 else Vector2.ZERO
	var finish: Vector2 = finish_value if finish_value is Vector2 else Vector2.ZERO
	check(start.distance_to(finish) <= 18.01, "Projectile trails must remain bounded after long frame or camera movement.")

	var equipped_value: Variant = runtime.get("equipped_items")
	var equipped: Dictionary = equipped_value as Dictionary if typeof(equipped_value) == TYPE_DICTIONARY else {}
	equipped["weapon"] = "clockglass_dartcaster"
	runtime.set("equipped_items", equipped)
	var weapon: Dictionary = runtime.call("equipped_ranged_weapon_data")
	check(not weapon.is_empty(), "Reference Dartcaster must resolve as ranged equipment.")
	if not weapon.is_empty():
		var ammo_id := ArsenalCatalog.weapon_ammunition_id(weapon)
		var inventory_value: Variant = runtime.get("inventory")
		var inventory: Dictionary = inventory_value as Dictionary if typeof(inventory_value) == TYPE_DICTIONARY else {}
		inventory["clockglass_dartcaster"] = 1
		inventory[ammo_id] = 9
		runtime.set("inventory", inventory)
		runtime.set("loaded_ammo", {"clockglass_dartcaster": 2})
		var arsenal: Dictionary = overlay.call("arsenal_status_snapshot")
		check(int(arsenal.get("loaded", -1)) == 2, "Presentation ammo status must read exact loaded rounds.")
		check(int(arsenal.get("reserve", -1)) == 9, "Presentation ammo status must read reserve inventory.")

	runtime.set("runtime_entities", [{
		"placement_id": "test_boss",
		"object_id": "test_boss_object",
		"position": Vector2(320, 220),
		"health": 12,
		"active": true,
		"definition": {
			"id": "test_boss_object",
			"display_name": "Test Sentinel",
			"kind": "enemy",
			"max_health": 20,
			"boss": {
				"enabled": true,
				"phases": [{
					"id": "test_phase",
					"display_name": "Test Phase",
					"health_ratio_at_or_below": 1.0,
					"available_eras": []
				}]
			}
		}
	}])
	runtime.set("engaged_bosses", {"test_boss": true})
	runtime.set("boss_phase_ids", {"test_boss": "test_phase"})
	var boss: Dictionary = overlay.call("boss_status_snapshot")
	check(str(boss.get("name", "")) == "Test Sentinel", "Boss overlay must read the active boss display name.")
	check(int(boss.get("health", -1)) == 12 and int(boss.get("maximum", -1)) == 20, "Boss overlay must read exact current and maximum health.")
	check(str(boss.get("phase", "")) == "Test Phase", "Boss overlay must resolve the active authored phase name.")

	check(bool(overlay.call("presentation_world_layers_allowed")), "Normal gameplay must allow presentation-owned combat layers.")
	runtime.set("flow", 5)
	check(not bool(overlay.call("presentation_world_layers_allowed")), "Paused gameplay must not redraw world layers above the root pause panel.")

	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Combat readability smoke test passed: projectile camera conversion, shared depth, ammo HUD, boss status, duplicate suppression and pause layering are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
