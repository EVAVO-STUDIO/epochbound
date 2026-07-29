extends SceneTree

const ItemForgeStudio = preload("res://addons/epochbound_item_forge/item_forge_studio.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := ItemForgeStudio.new()
	root.add_child(studio)

	var item_list_value: Variant = studio.get("item_list")
	var recipe_list_value: Variant = studio.get("recipe_list")
	var output_selector_value: Variant = studio.get("recipe_output_selector")
	var starting_recipe_list_value: Variant = studio.get("starting_recipe_list")
	check(item_list_value is ItemList, "Item Forge must create its item list.")
	check(recipe_list_value is ItemList, "Item Forge must create its recipe list.")
	check(output_selector_value is OptionButton, "Item Forge must create its recipe output selector.")
	check(starting_recipe_list_value is ItemList, "Item Forge must create its starting-recipe list.")

	if item_list_value is ItemList:
		check((item_list_value as ItemList).item_count == 6, "Item Forge must display all six reference items.")
	if recipe_list_value is ItemList:
		check((recipe_list_value as ItemList).item_count == 2, "Item Forge must display both reference recipes.")
	if starting_recipe_list_value is ItemList:
		check((starting_recipe_list_value as ItemList).item_count == 2, "Starting loadout must list both reference recipes.")

	var selected_recipe_id := str(studio.get("selected_recipe_id"))
	check(not selected_recipe_id.is_empty(), "Item Forge must select an initial recipe.")
	var recipe_definitions_value: Variant = studio.get("recipe_definitions")
	var recipe_definitions: Dictionary = recipe_definitions_value if typeof(recipe_definitions_value) == TYPE_DICTIONARY else {}
	var selected_recipe := ItemCatalog.recipe(recipe_definitions, selected_recipe_id)
	check(not selected_recipe.is_empty(), "The initial Item Forge recipe must resolve from the shared catalog.")
	if output_selector_value is OptionButton and not selected_recipe.is_empty():
		var output_selector := output_selector_value as OptionButton
		check(output_selector.item_count == 6, "Recipe output selector must contain every reference item.")
		check(output_selector.selected >= 0, "Recipe output selector must retain a selection.")
		if output_selector.selected >= 0:
			var actual_output_id := str(output_selector.get_item_metadata(output_selector.selected))
			var expected_output_id := str(InventoryModel.recipe_output(selected_recipe).get("item_id", ""))
			check(
				actual_output_id == expected_output_id,
				"Recipe inspector must preserve the authored output item after selector population."
			)

	var starting_inventory_value: Variant = studio.get("starting_inventory_edit")
	if starting_inventory_value is TextEdit:
		var starting_text := (starting_inventory_value as TextEdit).text
		check(starting_text.contains("museum_tonic = 1"), "Starting loadout editor must show Museum Tonic.")
		check(starting_text.contains("brass_filings = 1"), "Starting loadout editor must show Brass Filings.")
	else:
		failures.append("Item Forge must create its starting-inventory editor.")

	root.remove_child(studio)
	studio.free()
	finish()


func finish() -> void:
	if failures.is_empty():
		print("Item Forge editor smoke test passed: catalogs, recipe output selection and starting loadout are represented correctly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
