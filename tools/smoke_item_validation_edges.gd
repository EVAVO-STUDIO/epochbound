extends SceneTree

const ItemValidator = preload("res://src/content/item_validator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var items: Dictionary = {
		"brass_filings": {"id": "brass_filings"},
		"ashen_resin": {"id": "ashen_resin"},
		"archivist_lens": {"id": "archivist_lens"},
		"archive_bolts": {"id": "archive_bolts"}
	}
	var recipes: Dictionary = {
		"ember_salve_recipe": {"id": "ember_salve_recipe"},
		"clockglass_lens_recipe": {"id": "clockglass_lens_recipe"}
	}

	var errors: Array[String] = []
	var used_items: Dictionary = {}
	ItemValidator.validate_grants("not-an-array", "edge/grants", items, used_items, errors)
	check(has_message(errors, "must be an array"), "Grant validation must reject non-array values.")

	errors.clear()
	ItemValidator.validate_grants(["not-an-object"], "edge/grants", items, used_items, errors)
	check(has_message(errors, "must be objects"), "Grant validation must reject non-object entries.")

	errors.clear()
	ItemValidator.validate_grants(
		[
			{"item_id": "brass_filings", "quantity": 1},
			{"item_id": "brass_filings", "quantity": 2}
		],
		"edge/grants",
		items,
		used_items,
		errors
	)
	check(has_message(errors, "is repeated"), "Grant validation must reject duplicate item IDs.")

	errors.clear()
	ItemValidator.validate_grants(
		[{"item_id": "ashen_resin", "quantity": 0}],
		"edge/grants",
		items,
		used_items,
		errors
	)
	check(has_message(errors, "must be positive"), "Grant validation must reject zero quantities.")

	errors.clear()
	ItemValidator.validate_grants(
		[{"item_id": "missing_item", "quantity": 1}],
		"edge/grants",
		items,
		used_items,
		errors
	)
	check(has_message(errors, "unknown item"), "Grant validation must reject unknown item IDs.")

	var used_recipes: Dictionary = {}
	errors.clear()
	ItemValidator.validate_recipe_unlocks("not-an-array", "edge/unlocks", recipes, used_recipes, errors)
	check(has_message(errors, "must be an array"), "Recipe-unlock validation must reject non-array values.")

	errors.clear()
	ItemValidator.validate_recipe_unlocks([42], "edge/unlocks", recipes, used_recipes, errors)
	check(has_message(errors, "must be a string ID"), "Recipe-unlock validation must reject non-string IDs.")

	errors.clear()
	ItemValidator.validate_recipe_unlocks(
		["ember_salve_recipe", "ember_salve_recipe"],
		"edge/unlocks",
		recipes,
		used_recipes,
		errors
	)
	check(has_message(errors, "is repeated"), "Recipe-unlock validation must reject duplicate IDs.")

	errors.clear()
	ItemValidator.validate_recipe_unlocks(
		["missing_recipe"],
		"edge/unlocks",
		recipes,
		used_recipes,
		errors
	)
	check(has_message(errors, "unknown recipe"), "Recipe-unlock validation must reject unknown IDs.")

	errors.clear()
	used_recipes.clear()
	ItemValidator.validate_recipe_unlocks(
		["clockglass_lens_recipe"],
		"edge/unlocks",
		recipes,
		used_recipes,
		errors
	)
	check(errors.is_empty(), "A valid recipe unlock must pass validation.")
	check(bool(used_recipes.get("clockglass_lens_recipe", false)), "A valid unlock must mark its recipe as used.")

	var authored_used_items: Dictionary = {}
	var authored_used_recipes: Dictionary = {}
	ItemValidator.collect_authored_item_and_recipe_uses(
		{
			"starting_equipment": {"tool": "archivist_lens"},
			"quests": [{
				"rewards": [{
					"type": "grant_item",
					"item_id": "archivist_lens",
					"quantity": 1
				}]
			}],
			"merchants": [{
				"stock": [{"item_id": "archive_bolts", "quantity": 12}]
			}],
			"unlock_recipes": ["clockglass_lens_recipe"],
			"effects": [{
				"type": "unlock_recipe",
				"recipe_id": "ember_salve_recipe"
			}],
			"unknown": {"item_id": "missing_item"}
		},
		items,
		recipes,
		authored_used_items,
		authored_used_recipes
	)
	check(
		bool(authored_used_items.get("archivist_lens", false)),
		"Starting equipment and story rewards must count as authored item usage."
	)
	check(
		bool(authored_used_items.get("archive_bolts", false)),
		"Merchant stock must count as authored item usage."
	)
	check(
		not authored_used_items.has("missing_item"),
		"Unknown cross-domain references must not hide missing item definitions."
	)
	check(
		bool(authored_used_recipes.get("clockglass_lens_recipe", false)),
		"List-style discovery unlocks must count as authored recipe usage."
	)
	check(
		bool(authored_used_recipes.get("ember_salve_recipe", false)),
		"Typed cinematic and story unlock effects must count as recipe usage."
	)

	finish()


func has_message(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if message.contains(fragment):
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Item reward validation edge test passed: malformed grants and unlocks are rejected deterministically.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
