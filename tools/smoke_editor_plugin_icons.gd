extends SceneTree

const EditorPluginIcon = preload("res://addons/epochbound_editor_common/editor_plugin_icon.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var theme := Theme.new()
	var semantic_icon := make_icon(Color(0.25, 0.75, 1.0, 1.0))
	var fallback_icon := make_icon(Color(1.0, 0.35, 0.5, 1.0))
	theme.set_icon("SemanticIcon", EditorPluginIcon.EDITOR_ICON_THEME_TYPE, semantic_icon)
	theme.set_icon(EditorPluginIcon.FALLBACK_ICON, EditorPluginIcon.EDITOR_ICON_THEME_TYPE, fallback_icon)

	check(
		EditorPluginIcon.resolve_from_theme(theme, ["MissingIcon", "SemanticIcon"]) == semantic_icon,
		"The resolver must select the first available semantic candidate without probing a missing icon through get_icon()."
	)
	check(
		EditorPluginIcon.resolve_from_theme(theme, ["", "  ", "MissingIcon"]) == fallback_icon,
		"The resolver must ignore blank candidates and use the stable editor fallback."
	)
	check(
		EditorPluginIcon.resolve_from_theme(theme, []) == fallback_icon,
		"An empty candidate list must still resolve the stable editor fallback."
	)
	check(
		EditorPluginIcon.resolve_from_theme(Theme.new(), ["MissingIcon"]) == null,
		"A theme without any safe icon must fail quietly instead of requesting an invalid theme item."
	)
	check(
		EditorPluginIcon.resolve_from_theme(null, ["SemanticIcon"]) == null,
		"A missing editor theme must fail quietly."
	)
	finish()


func make_icon(color: Color) -> Texture2D:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Editor plugin icon smoke test passed: semantic candidates, blank filtering, stable fallback and quiet failure remain deterministic.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
