#!/usr/bin/env python3
"""Fail closed when Epochbound's regional supply integration drifts."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        errors.append(f"missing required file: {relative_path}")
        return ""
    return path.read_text(encoding="utf-8")


def require(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{relative_path}: missing {token}")


def forbid(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{relative_path}: contains forbidden {token}")


catalog = read("src/content/supply_region_catalog.gd")
require(
    "src/content/supply_region_catalog.gd",
    catalog,
    [
        "MIN_INTERVAL_SECONDS := 30.0",
        "MAX_INTERVAL_SECONDS := 86400.0",
        "MAX_CATCHUP_CYCLES := 32",
        'campaign.get("economy_files", [])',
        'data.get("supply_regions", [])',
        "interval_seconds",
        "max_catchup_cycles",
        "merchant_region_id",
        "stock_restock_quantity",
        "stock_restock_target",
        "stock_is_renewable",
        "format_duration",
    ],
)

model = read("src/game/supply_region_model.gd")
require(
    "src/game/supply_region_model.gd",
    model,
    [
        "cycle_at",
        "seconds_until_next_cycle",
        "initial_cycles",
        "sanitize_cycles",
        "apply_due_restock",
        "cycles_advanced",
        "applied_cycles",
        "discarded_cycles",
        "region_cycles[region_id] = current_cycle",
        "stock_restock_target",
        "stock_restock_quantity",
        "merchant_has_renewable_stock",
        "sorted_ids",
    ],
)
forbid(
    "src/game/supply_region_model.gd",
    model,
    [
        "Time.get_unix_time",
        "Time.get_datetime",
        "OS.get_unix_time",
        "DateTime",
        "offline_seconds",
    ],
)

validator = read("src/content/supply_region_validator.gd")
require(
    "src/content/supply_region_validator.gd",
    validator,
    [
        'BaseValidator = preload("res://src/content/economy_validator.gd")',
        "validate_all",
        "validate_campaign_path",
        "validate_profile",
        "validate_supply_only",
        "validate_catalog_file",
        "validate_region_records",
        "validate_profile_supply",
        "supply_region_count",
        "renewable_stock_count",
        "renewable stock requires the merchant to declare supply_region_id",
        "only consumable, material or ammunition stock may replenish automatically",
        "unlimited stock cannot define replenishment fields",
        "restock_target cannot be lower than the initial quantity",
        "Save supply_region_cycles references unknown region",
    ],
)

complete_validator = read("src/content/complete_content_validator.gd")
require(
    "src/content/complete_content_validator.gd",
    complete_validator,
    [
        'BaseValidator = preload("res://src/content/sprite_animation_strict_validator.gd")',
        'SupplyValidator = preload("res://src/content/supply_region_validator.gd")',
        "validate_all",
        "validate_campaign_path",
        "validate_profile",
        "validate_supply_only",
        "validate_profile_supply",
        "supply_region_count",
        "renewable_stock_count",
    ],
)

runtime_base = read("src/presentation_runtime_base.gd")
require(
    "src/presentation_runtime_base.gd",
    runtime_base,
    [
        'extends "res://src/cinematic_runtime.gd"',
        "player_settings_contract_ok",
        "presentation_overlay_handles_combat_readability",
        "root_presentation_suppression_contract_ok",
    ],
)

runtime = read("src/presentation_runtime_current.gd")
require(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        'extends "res://src/hideaway_runtime.gd"',
        'CompleteValidator = preload("res://src/content/complete_content_validator.gd")',
        'SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")',
        'SupplyModel = preload("res://src/game/supply_region_model.gd")',
        "supply_region_definitions",
        "supply_region_cycles",
        "supply_regions_initialized",
        "load_economy_catalogs",
        "reset_economy_state",
        "apply_due_supply_restock",
        "record_supply_change",
        "supply_region_status_text",
        "capture_save_profile",
        'payload["supply_region_cycles"]',
        'payload["supply_regions_initialized"]',
        "CompleteValidator.validate_profile",
        'request_autosave("Regional supply caught up")',
        '"supply_region_cycles": supply_region_cycles',
        "supply_runtime_contract_ok",
    ],
)
forbid(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        "Time.get_unix_time",
        "Time.get_datetime",
        "DateTime",
        "offline_seconds",
    ],
)

scene = read("src/app.tscn")
require("src/app.tscn", scene, ['res://src/presentation_runtime_current.gd'])

runtime_contract = read("src/game/runtime_scene_contract.gd")
require(
    "src/game/runtime_scene_contract.gd",
    runtime_contract,
    [
        'CURRENT_RUNTIME_SCRIPT := "res://src/presentation_runtime_current.gd"',
        '"apply_due_supply_restock"',
        '"supply_region_status_text"',
        '"supply_runtime_contract_ok"',
        "Runtime root did not initialise every regional supply cycle",
    ],
)

reference_economy = read("campaigns/epochbound_demo/economy/core.json")
require(
    "campaigns/epochbound_demo/economy/core.json",
    reference_economy,
    [
        '"supply_regions"',
        '"bellweather_route"',
        '"underworks_route"',
        '"supply_region_id"',
        '"restock_interval_seconds"',
        '"max_catchup_cycles"',
        '"restock_quantity"',
        '"restock_target"',
        '"museum_flashlight"',
        '"clockglass_fragment"',
        '"clockglass_dartcaster"',
    ],
)

trade = read("addons/epochbound_trade_studio/trade_studio_supply.gd")
require(
    "addons/epochbound_trade_studio/trade_studio_supply.gd",
    trade,
    [
        'extends "res://addons/epochbound_trade_studio/trade_studio.gd"',
        "build_supply_regions_tab",
        "supply_region_list",
        "merchant_supply_region_selector",
        "add_supply_region",
        "apply_supply_region",
        "delete_supply_region",
        "Cannot delete",
        'data["supply_region_id"]',
        "SupplyValidator.validate_campaign_path",
        "Change rolled back",
    ],
)
require(
    "addons/epochbound_trade_studio/plugin.gd",
    read("addons/epochbound_trade_studio/plugin.gd"),
    ['res://addons/epochbound_trade_studio/trade_studio_supply.gd'],
)

state_studio = read("addons/epochbound_save_state_studio/save_state_studio_supply.gd")
require(
    "addons/epochbound_save_state_studio/save_state_studio_supply.gd",
    state_studio,
    [
        'extends "res://addons/epochbound_save_state_studio/save_state_studio.gd"',
        'supply_cycle_list.name = "Supply Cycles"',
        "supply_region_cycles",
        "supply_regions_initialized",
        "REGIONAL SUPPLY",
        "CompleteValidator.validate_campaign_path",
        "CompleteValidator.validate_profile",
    ],
)
require(
    "addons/epochbound_save_state_studio/plugin.gd",
    read("addons/epochbound_save_state_studio/plugin.gd"),
    ['res://addons/epochbound_save_state_studio/save_state_studio_supply.gd'],
)

package_studio = read("addons/epochbound_package_studio/package_studio_supply.gd")
require(
    "addons/epochbound_package_studio/package_studio_supply.gd",
    package_studio,
    [
        'extends "res://addons/epochbound_package_studio/package_studio_current.gd"',
        'SupplyCompleteValidator = preload("res://src/content/complete_content_validator.gd")',
        "SupplyCompleteValidator.validate_campaign_path",
        "SupplyCompleteValidator.validate_all",
        "populate_release_fields",
    ],
)
require(
    "addons/epochbound_package_studio/plugin.gd",
    read("addons/epochbound_package_studio/plugin.gd"),
    ['res://addons/epochbound_package_studio/package_studio_supply.gd'],
)

install_service = read("src/content/campaign_install_service.gd")
require(
    "src/content/campaign_install_service.gd",
    install_service,
    [
        'CurrentValidator = preload("res://src/content/complete_content_validator.gd")',
        "CurrentValidator.validate_campaign_path",
        "fully validated campaign installation",
    ],
)

audit = read("src/content/supply_campaign_audit.gd")
require(
    "src/content/supply_campaign_audit.gd",
    audit,
    [
        'BaseAudit = preload("res://src/content/campaign_audit.gd")',
        "SupplyValidator.validate_supply_only",
        '"supply.invalid"',
        '"supply.review"',
        'metrics["supply_region_count"]',
        'metrics["renewable_stock_count"]',
        "BaseAudit.build_report",
    ],
)
audit_studio = read("addons/epochbound_campaign_audit/campaign_audit_supply.gd")
require(
    "addons/epochbound_campaign_audit/campaign_audit_supply.gd",
    audit_studio,
    [
        'extends "res://addons/epochbound_campaign_audit/campaign_audit_studio.gd"',
        "SupplyCampaignAudit.audit_campaign_path",
        "Supply regions %d",
        "Renewable stock %d",
    ],
)
require(
    "addons/epochbound_campaign_audit/plugin.gd",
    read("addons/epochbound_campaign_audit/plugin.gd"),
    ['res://addons/epochbound_campaign_audit/campaign_audit_supply.gd'],
)

validate_content = read("tools/validate_content.gd")
require(
    "tools/validate_content.gd",
    validate_content,
    [
        'FinalValidator = preload("res://src/content/complete_content_validator.gd")',
        "supply region(s)",
        "renewable stock entry(s)",
    ],
)
require(
    "tools/audit_campaigns.gd",
    read("tools/audit_campaigns.gd"),
    ['CampaignAudit = preload("res://src/content/supply_campaign_audit.gd")'],
)

compile_probe = read("tools/compile_supply_region_probe.gd")
require(
    "tools/compile_supply_region_probe.gd",
    compile_probe,
    [
        "supply_region_catalog.gd",
        "supply_region_validator.gd",
        "complete_content_validator.gd",
        "supply_campaign_audit.gd",
        "campaign_install_service.gd",
        "supply_region_model.gd",
        "presentation_runtime_base.gd",
        "presentation_runtime_current.gd",
        "trade_studio_supply.gd",
        "save_state_studio_supply.gd",
        "package_studio_supply.gd",
        "campaign_audit_supply.gd",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
        "smoke_package_current_validation.gd",
        "app.tscn",
    ],
)

runtime_smoke = read("tools/smoke_supply_regions.gd")
require(
    "tools/smoke_supply_regions.gd",
    runtime_smoke,
    [
        "bounded catch-up",
        "Scarce equipment must never replenish automatically",
        "Progression stock must remain scarce",
        "A full-stock route must still consume its elapsed cycle",
        "The same supply cycle must be idempotent",
        "Captured saves must persist the exact Bellweather cycle",
        "Loading a saved cycle must not duplicate its delivery",
        "A pre-supply current-schema profile must remain loadable",
        "must not receive a retroactive windfall",
    ],
)
edge_smoke = read("tools/smoke_supply_validation_edges.gd")
require(
    "tools/smoke_supply_validation_edges.gd",
    edge_smoke,
    [
        "Invalid supply route IDs must be rejected",
        "Unlimited stock must reject replenishment fields",
        "Equipment must remain outside automatic restocking",
        "Renewable stock must require a merchant route",
        "Saved cycles cannot exceed",
        "Initialised profiles must contain every declared route cursor",
    ],
)
trade_smoke = read("tools/smoke_trade_studio.gd")
require(
    "tools/smoke_trade_studio.gd",
    trade_smoke,
    [
        "trade_studio_supply.gd",
        "supply route list",
        "restock_quantity",
        "supply_region_count",
        "renewable_stock_count",
    ],
)
state_smoke = read("tools/smoke_save_state_studio.gd")
require(
    "tools/smoke_save_state_studio.gd",
    state_smoke,
    [
        "save_state_studio_supply.gd",
        "regional supply-cycle inspector",
        "REGIONAL SUPPLY",
        '"supply_region_cycles"',
        '"supply_regions_initialized"',
    ],
)
audit_smoke = read("tools/smoke_campaign_audit.gd")
require(
    "tools/smoke_campaign_audit.gd",
    audit_smoke,
    ["supply_campaign_audit.gd", "supply_region_count", "renewable_stock_count"],
)
audit_studio_smoke = read("tools/smoke_campaign_audit_studio.gd")
require(
    "tools/smoke_campaign_audit_studio.gd",
    audit_studio_smoke,
    [
        "campaign_audit_supply.gd",
        "Supply regions 2",
        "Renewable stock 5",
        "Exported report must preserve supply-route evidence",
    ],
)
package_smoke = read("tools/smoke_package_current_validation.gd")
require(
    "tools/smoke_package_current_validation.gd",
    package_smoke,
    [
        "INVALID_SUPPLY_PACKAGE",
        "invalid_supply_bytes",
        'merchant["supply_region_id"] = "missing_route"',
        "Invalid-supply package must remain structurally and cryptographically valid",
        "Rejected supply package must never be promoted",
    ],
)

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        "compile_supply_region_probe.gd",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
        "regional supply",
        "scarcity",
    ],
)

for workflow_path in [
    ".github/workflows/validate.yml",
    ".github/workflows/audio-mood-validation.yml",
    ".github/workflows/sprite-animation-validation.yml",
]:
    require(
        workflow_path,
        read(workflow_path),
        ["python3 tools/check_supply_region_contract.py"],
    )

for workflow_path in [
    ".github/workflows/audio-mood-validation.yml",
    ".github/workflows/sprite-animation-validation.yml",
]:
    require(
        workflow_path,
        read(workflow_path),
        [
            "compile_supply_region_probe.gd",
            "smoke_supply_regions.gd",
            "smoke_supply_validation_edges.gd",
        ],
    )

release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        "python3 tools/check_supply_region_contract.py",
        "compile_supply_region_probe.gd",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
    ],
)

require(
    "docs/MERCHANT_ECONOMY_STUDIO.md",
    read("docs/MERCHANT_ECONOMY_STUDIO.md"),
    [
        "Supply routes and scarcity",
        "restock_interval_seconds",
        "max_catchup_cycles",
        "restock_quantity",
        "restock_target",
        "play_time_seconds",
        "No offline windfalls",
        "Old-save compatibility",
        "Supply Cycles",
    ],
)
require(
    "docs/ECONOMY_PLAYTEST_CHECKLIST.md",
    read("docs/ECONOMY_PLAYTEST_CHECKLIST.md"),
    [
        "Regional supply and scarcity",
        "Full-stock cycle",
        "Bounded catch-up",
        "Old save compatibility",
        "Progression equipment scarcity",
    ],
)
require(
    "README.md",
    read("README.md"),
    [
        "regional supply routes",
        "bounded restocking",
        "authored scarcity",
        "Supply Cycles",
        "Regional supply and scarcity",
    ],
)

if errors:
    print("Epochbound regional supply contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_supply_region_contract_passed")
print("- supply routes use durable gameplay time with bounded catch-up and no offline windfalls")
print("- only recovery materials consumables and ammunition replenish; equipment and progression stock remain scarce")
print("- cycle cursors persist through saves including full-stock cycles and old-save initialisation")
print("- Trade State Package installation Audit compile local and governed workflow gates cover the integration")
