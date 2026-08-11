extends SceneTree

const TARGETS := [
	"res://src/content/localisation_layout.gd",
	"res://src/content/economy_catalog.gd",
	"res://src/content/economy_validator.gd",
	"res://src/content/supply_region_catalog.gd",
	"res://src/content/supply_region_validator.gd",
	"res://src/content/complete_content_validator.gd",
	"res://src/content/supply_campaign_audit.gd",
	"res://src/content/campaign_install_service.gd",
	"res://src/game/economy_model.gd",
	"res://src/game/supply_region_model.gd",
	"res://src/presentation_runtime_base.gd",
	"res://src/presentation_runtime_current.gd",
	"res://src/game/runtime_scene_contract.gd",
	"res://addons/epochbound_trade_studio/trade_studio.gd",
	"res://addons/epochbound_trade_studio/trade_studio_supply.gd",
	"res://addons/epochbound_trade_studio/plugin.gd",
	"res://addons/epochbound_save_state_studio/save_state_studio.gd",
	"res://addons/epochbound_save_state_studio/save_state_studio_supply.gd",
	"res://addons/epochbound_save_state_studio/plugin.gd",
	"res://addons/epochbound_package_studio/package_studio.gd",
	"res://addons/epochbound_package_studio/package_studio_current.gd",
	"res://addons/epochbound_package_studio/package_studio_supply.gd",
	"res://addons/epochbound_package_studio/plugin.gd",
	"res://addons/epochbound_campaign_audit/campaign_audit_studio.gd",
	"res://addons/epochbound_campaign_audit/campaign_audit_supply.gd",
	"res://addons/epochbound_campaign_audit/plugin.gd",
	"res://tools/validate_content.gd",
	"res://tools/audit_campaigns.gd",
	"res://tools/smoke_runtime_scene_contract.gd",
	"res://tools/compile_localisation_probe.gd",
	"res://tools/compile_localisation_layout_probe.gd",
	"res://tools/smoke_localisation.gd",
	"res://tools/smoke_localisation_layout.gd",
	"res://tools/smoke_supply_regions.gd",
	"res://tools/smoke_supply_validation_edges.gd",
	"res://tools/smoke_trade_studio.gd",
	"res://tools/smoke_save_state_studio.gd",
	"res://tools/smoke_campaign_audit.gd",
	"res://tools/smoke_campaign_audit_studio.gd",
	"res://tools/smoke_package_current_validation.gd",
	"res://src/app.tscn"
]

var failures: Array[String] = []


func _initialize() -> void:
	for path in TARGETS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			failures.append("Could not load or compile %s." % path)
			continue
		if path.ends_with(".gd") and not resource is GDScript:
			failures.append("Expected a GDScript resource at %s." % path)
		elif path.ends_with(".tscn") and not resource is PackedScene:
			failures.append("Expected a PackedScene resource at %s." % path)
	if failures.is_empty():
		print("Regional supply compile probe passed: catalogues, validators, deterministic model, canonical runtime, measured localisation layout, Trade, State, Package, staged installation, Audit and regressions load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
