extends SceneTree

const PackageStudio = preload("res://addons/epochbound_package_studio/package_studio.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var studio := PackageStudio.new()
	root.add_child(studio)
	var selector: Variant = studio.get("campaign_selector")
	var version: Variant = studio.get("version_edit")
	var packages: Variant = studio.get("package_list")
	var replace: Variant = studio.get("replace_check")
	check(selector is OptionButton and (selector as OptionButton).item_count >= 1, "Package Studio must discover source campaigns.")
	check(version is LineEdit and (version as LineEdit).text == "0.1.0", "Package Studio must expose semantic release version metadata.")
	check(packages is ItemList, "Package Studio must expose exported package inventory.")
	check(replace is CheckBox, "Package Studio must require explicit replacement consent.")
	var authored: Variant = studio.call("authored_release")
	check(typeof(authored) == TYPE_DICTIONARY, "Package Studio must produce one release metadata object.")
	if typeof(authored) == TYPE_DICTIONARY:
		check(str((authored as Dictionary).get("channel", "")) == "development", "Package Studio must preserve the authored release channel.")
	root.remove_child(studio)
	studio.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Package Studio smoke test passed: campaign discovery, release metadata and safe-install controls are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
