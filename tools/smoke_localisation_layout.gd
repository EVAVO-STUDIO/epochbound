extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")
const LocalisationLayout = preload("res://src/content/localisation_layout.gd")

const REFERENCE_CAMPAIGN := "res://campaigns/epochbound_demo/campaign.json"
const PSEUDO := LocalisationCatalog.PSEUDO_LOCALE

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	test_layout_primitives()
	test_ui_surface_budgets()
	test_reference_intro_budget()
	finish()


func test_layout_primitives() -> void:
	var font := ThemeDB.fallback_font
	check(font != null, "Godot must provide a fallback Font for deterministic layout measurement.")
	check(LocalisationLayout.localisation_layout_contract_ok(), "Localisation layout utility contract must remain valid.")
	if font == null:
		return

	var single := LocalisationLayout.fit_single_line(font, "MEASURED COPY", 14, 8, 240.0)
	check(bool(single.get("ok", false)), "Ordinary single-line copy must fit a valid surface.")
	check(str(single.get("text", "")) == "MEASURED COPY", "Fitting must preserve copy that already fits.")
	check(not bool(single.get("truncated", true)), "Copy that fits must not be marked truncated.")
	check(float(single.get("width", INF)) <= 240.0 + LocalisationLayout.WIDTH_EPSILON, "Measured single-line copy must remain inside its width.")

	var newline := LocalisationLayout.fit_single_line(font, "ONE\nTWO", 12, 8, 160.0)
	check(str(newline.get("text", "")) == "ONE TWO", "Single-line fitting must normalize embedded line breaks deterministically.")

	var long_text := "THIS IS AN INTENTIONALLY LONG LOCALISATION STRING THAT CANNOT FIT THE DECLARED SURFACE AT ITS MINIMUM SIZE"
	var clipped := LocalisationLayout.fit_single_line(font, long_text, 12, 8, 120.0)
	check(bool(clipped.get("ok", false)), "Bounded single-line fitting must return a drawable result at the minimum size.")
	check(bool(clipped.get("truncated", false)), "Impossible single-line copy must report visible truncation.")
	check(str(clipped.get("text", "")).ends_with(LocalisationLayout.ELLIPSIS), "Truncated copy must use the stable ellipsis marker.")
	check(float(clipped.get("width", INF)) <= 120.0 + LocalisationLayout.WIDTH_EPSILON, "Truncated copy must remain inside the measured width.")
	check(clipped == LocalisationLayout.fit_single_line(font, long_text, 12, 8, 120.0), "Single-line fitting must be deterministic.")

	var block_text := "A bounded block wraps on stable word boundaries and reduces its size only inside the authored range."
	var block := LocalisationLayout.fit_block(font, block_text, 15, 9, 220.0, 3, 40.0, 4.0)
	check(bool(block.get("ok", false)), "A normal bounded text block must fit.")
	var lines_value: Variant = block.get("lines", [])
	var lines: Array = lines_value if typeof(lines_value) == TYPE_ARRAY else []
	check(not lines.is_empty() and lines.size() <= 3, "Fitted blocks must respect the authored line limit.")
	check(LocalisationLayout.lines_fit(font, lines, int(block.get("font_size", 9)), 220.0), "Every fitted block line must remain within the measured width.")
	check(float(block.get("height", INF)) <= 40.0 + LocalisationLayout.WIDTH_EPSILON, "Fitted blocks must remain inside the declared height budget.")
	check(block == LocalisationLayout.fit_block(font, block_text, 15, 9, 220.0, 3, 40.0, 4.0), "Block fitting must be deterministic.")

	var impossible := LocalisationLayout.fit_single_line(font, "TEXT", 10, 8, 0.0)
	check(not bool(impossible.get("ok", true)), "A zero-width single-line surface must fail closed.")
	var impossible_block := LocalisationLayout.fit_block(font, "TEXT", 10, 8, 100.0, 2, 0.0, 2.0)
	check(not bool(impossible_block.get("ok", true)), "A zero-height block must fail closed.")


func test_ui_surface_budgets() -> void:
	var font := ThemeDB.fallback_font
	var catalog := LocalisationCatalog.load_ui_catalog()
	check(bool(catalog.get("ok", false)), "The shared UI catalogue must load for layout validation.")
	if font == null or not bool(catalog.get("ok", false)):
		return

	var single_surfaces := [
		{"key": "ui.title.continue", "fallback": "CONTINUE", "width": 330.0, "preferred": 16, "minimum": 10},
		{"key": "ui.title.new_journey", "fallback": "NEW JOURNEY", "width": 330.0, "preferred": 16, "minimum": 10},
		{"key": "ui.title.options", "fallback": "OPTIONS", "width": 330.0, "preferred": 16, "minimum": 10},
		{"key": "ui.title.confirm_select", "fallback": "{confirm}  CONFIRM     ARROWS  SELECT", "replacements": {"confirm": "E / Z / A"}, "width": 616.0, "preferred": 10, "minimum": 6},
		{"key": "ui.campaigns.heading", "fallback": "CHOOSE A CAMPAIGN", "width": 616.0, "preferred": 20, "minimum": 10},
		{"key": "ui.campaigns.subtitle", "fallback": "Authored journeys share one runtime contract", "width": 616.0, "preferred": 10, "minimum": 6},
		{"key": "ui.campaigns.built_in", "fallback": "BUILT-IN", "width": 90.0, "preferred": 9, "minimum": 6},
		{"key": "ui.options.title", "fallback": "OPTIONS", "width": 210.0, "preferred": 18, "minimum": 10},
		{"key": "ui.options.header", "fallback": "PLAYER LOCAL  •  VERSIONED  •  RECOVERABLE  •  REMAPPABLE", "width": 248.0, "preferred": 7, "minimum": 5},
		{"key": "ui.options.footer", "fallback": "{confirm} SELECT   •   LEFT / RIGHT CHANGE   •   ESC / O BACK", "replacements": {"confirm": "E / A"}, "width": 476.0, "preferred": 7, "minimum": 5},
		{"key": "ui.controls.title", "fallback": "CONTROLS — {device}", "replacements": {"device": "CONTROLLER"}, "width": 230.0, "preferred": 16, "minimum": 9},
		{"key": "ui.controls.header", "fallback": "14 GAMEPLAY ACTIONS  •  ESC / O / START RESERVED", "width": 248.0, "preferred": 7, "minimum": 5},
		{"key": "ui.controls.footer", "fallback": "{confirm} REBIND   •   LEFT / RIGHT DEVICE   •   ESC BACK", "replacements": {"confirm": "E / A"}, "width": 476.0, "preferred": 7, "minimum": 5},
		{"key": "ui.controls.action.quick_item", "fallback": "QUICK RESTORATIVE", "width": 300.0, "preferred": 9, "minimum": 6},
		{"key": "ui.controls.capture_controller", "fallback": "PRESS A CONTROLLER INPUT — START CANCELS", "width": 476.0, "preferred": 7, "minimum": 5},
		{"key": "ui.intro.continue_skip", "fallback": "CONFIRM TO CONTINUE   •   ESC TO SKIP", "width": 616.0, "preferred": 10, "minimum": 6},
		{"key": "ui.hideaway.status.overview", "fallback": "{tier}   SALVAGE {salvage}/{salvage_cap}   RETURNS {returns}/{return_cap}", "replacements": {"tier": "ESTABLISHED REFUGE", "salvage": 99, "salvage_cap": 99, "returns": 3, "return_cap": 3}, "width": 464.0, "preferred": 9, "minimum": 5},
		{"key": "ui.hideaway.status.restoration", "fallback": "RESTORATION {total}/{maximum}   FACILITIES {restored}/{facilities}", "replacements": {"total": 12, "maximum": 12, "restored": 4, "facilities": 4}, "width": 464.0, "preferred": 8, "minimum": 5},
		{"key": "ui.hideaway.status.ready", "fallback": "RETURN TO THE ROAD WHEN READY", "width": 464.0, "preferred": 7, "minimum": 5},
		{"key": "ui.hideaway.status.facility.unrestored", "fallback": "{facility} UNRESTORED   COST {cost}   SALVAGE {salvage}", "replacements": {"facility": "SHELTERED COLDFRAME", "cost": 8, "salvage": 99}, "width": 464.0, "preferred": 8, "minimum": 5},
		{"key": "ui.hideaway.status.facility.active", "fallback": "{facility} L{level}/{maximum}   NEXT {cost}   PREP {prepared}/{capacity}", "replacements": {"facility": "SALVAGE WORKBENCH", "level": 2, "maximum": 3, "cost": 8, "prepared": 2, "capacity": 2}, "width": 464.0, "preferred": 8, "minimum": 5},
		{"key": "ui.hideaway.status.facility.complete", "fallback": "{facility} L{level}/{maximum}   FULLY RESTORED   PREP {prepared}/{capacity}", "replacements": {"facility": "SHELTERED COLDFRAME", "level": 3, "maximum": 3, "prepared": 3, "capacity": 3}, "width": 464.0, "preferred": 8, "minimum": 5},
		{"key": "ui.hideaway.status.mementos", "fallback": "MEMENTOS {unlocked}/{total}   MEMORIES FROM THE ROAD", "replacements": {"unlocked": 6, "total": 6}, "width": 464.0, "preferred": 8, "minimum": 5},
		{"key": "ui.hideaway.controls.mementos", "fallback": "INTERACT REMEMBER   •   NOTHING IS CONSUMED", "width": 464.0, "preferred": 7, "minimum": 5}
	]
	for surface_value in single_surfaces:
		var surface: Dictionary = surface_value
		var key := str(surface.get("key", ""))
		var fallback := str(surface.get("fallback", key))
		var replacements_value: Variant = surface.get("replacements", {})
		var replacements: Dictionary = replacements_value if typeof(replacements_value) == TYPE_DICTIONARY else {}
		var text := LocalisationCatalog.resolve(catalog, PSEUDO, key, fallback, replacements)
		assert_single_surface(
			font,
			key,
			text,
			int(surface.get("preferred", 10)),
			int(surface.get("minimum", 6)),
			float(surface.get("width", 100.0)),
			false
		)

	var messages_value: Variant = catalog.get("messages", {})
	var messages: Dictionary = messages_value if typeof(messages_value) == TYPE_DICTIONARY else {}
	for key_value in messages.keys():
		var key := str(key_value)
		if not key.begins_with("ui.settings.") and not key.begins_with("ui.controls.action."):
			continue
		var text := LocalisationCatalog.resolve(catalog, PSEUDO, key, key)
		assert_single_surface(font, key, text, 9, 6, 300.0, false)


func test_reference_intro_budget() -> void:
	var font := ThemeDB.fallback_font
	var campaign_result := Repository.read_json(REFERENCE_CAMPAIGN)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must parse for localisation layout validation.")
	if font == null or not bool(campaign_result.get("ok", false)):
		return
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog := LocalisationCatalog.load_catalogs(REFERENCE_CAMPAIGN, campaign)
	check(bool(catalog.get("ok", false)), "Reference campaign localisation must load for layout validation.")
	if not bool(catalog.get("ok", false)):
		return
	var intro_value: Variant = campaign.get("intro", [])
	var intro: Array = intro_value if typeof(intro_value) == TYPE_ARRAY else []
	var keys_value: Variant = campaign.get("intro_keys", [])
	var keys: Array = keys_value if typeof(keys_value) == TYPE_ARRAY else []
	check(intro.size() == keys.size() and not intro.is_empty(), "Reference intro must provide one localisation key per page.")
	for index in range(mini(intro.size(), keys.size())):
		var text := LocalisationCatalog.resolve(catalog, PSEUDO, str(keys[index]), str(intro[index]))
		assert_block_surface(font, "reference intro page %d" % (index + 1), text, 15, 9, 472.0, 3, 66.0, 5.0, false)


func assert_single_surface(
	font: Font,
	label: String,
	text: String,
	preferred_size: int,
	minimum_size: int,
	width: float,
	allow_truncation: bool
) -> void:
	var result := LocalisationLayout.fit_single_line(font, text, preferred_size, minimum_size, width)
	check(bool(result.get("ok", false)), "%s must produce a drawable bounded line." % label)
	check(float(result.get("width", INF)) <= width + LocalisationLayout.WIDTH_EPSILON, "%s must not overflow its declared pixel width." % label)
	var fitted_text := str(result.get("text", ""))
	check(not fitted_text.is_empty(), "%s must retain visible copy." % label)
	if not allow_truncation:
		check(not bool(result.get("truncated", false)), "%s must fit current pseudo-localised copy without truncation." % label)
	elif bool(result.get("truncated", false)):
		check(fitted_text.ends_with(LocalisationLayout.ELLIPSIS), "%s truncation must remain visible and deterministic." % label)
	check(result == LocalisationLayout.fit_single_line(font, text, preferred_size, minimum_size, width), "%s fitting must be deterministic." % label)


func assert_block_surface(
	font: Font,
	label: String,
	text: String,
	preferred_size: int,
	minimum_size: int,
	width: float,
	max_lines: int,
	max_height: float,
	line_gap: float,
	allow_truncation: bool
) -> void:
	var result := LocalisationLayout.fit_block(font, text, preferred_size, minimum_size, width, max_lines, max_height, line_gap)
	check(bool(result.get("ok", false)), "%s must produce a drawable bounded block." % label)
	var lines_value: Variant = result.get("lines", [])
	var lines: Array = lines_value if typeof(lines_value) == TYPE_ARRAY else []
	check(not lines.is_empty() and lines.size() <= max_lines, "%s must respect its authored line count." % label)
	check(LocalisationLayout.lines_fit(font, lines, int(result.get("font_size", minimum_size)), width), "%s lines must remain inside the measured width." % label)
	check(float(result.get("height", INF)) <= max_height + LocalisationLayout.WIDTH_EPSILON, "%s must remain inside its measured height budget." % label)
	if not allow_truncation:
		check(not bool(result.get("truncated", false)), "%s must fit current pseudo-localised copy without truncation." % label)
	check(result == LocalisationLayout.fit_block(font, text, preferred_size, minimum_size, width, max_lines, max_height, line_gap), "%s block fitting must be deterministic." % label)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Localisation layout smoke test passed: English and pseudo-localised fixed-viewport copy is measured, shrunk, wrapped or visibly ellipsised inside deterministic authored bounds.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
