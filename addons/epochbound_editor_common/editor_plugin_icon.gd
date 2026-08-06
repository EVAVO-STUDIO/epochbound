@tool
extends RefCounted

const EDITOR_ICON_THEME_TYPE := "EditorIcons"
const FALLBACK_ICON := "Node"


static func resolve(editor_interface: EditorInterface, candidates: Array) -> Texture2D:
	if editor_interface == null:
		return null
	return resolve_from_theme(editor_interface.get_editor_theme(), candidates)


static func resolve_from_theme(theme: Theme, candidates: Array) -> Texture2D:
	if theme == null:
		return null
	for candidate_value in candidates:
		var candidate := str(candidate_value).strip_edges()
		if candidate.is_empty():
			continue
		if theme.has_icon(candidate, EDITOR_ICON_THEME_TYPE):
			return theme.get_icon(candidate, EDITOR_ICON_THEME_TYPE)
	if theme.has_icon(FALLBACK_ICON, EDITOR_ICON_THEME_TYPE):
		return theme.get_icon(FALLBACK_ICON, EDITOR_ICON_THEME_TYPE)
	return null
