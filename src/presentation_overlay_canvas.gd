extends "res://src/presentation_overlay.gd"


func runtime_root() -> Node:
	var layer := get_parent()
	return layer.get_parent() if layer != null else null


func draw_corner_brackets(rect: Rect2, color: Color) -> void:
	var length := 18.0
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y),
		rect.end
	]
	for corner: Vector2 in corners:
		var horizontal_direction := 1.0 if is_equal_approx(corner.x, rect.position.x) else -1.0
		var vertical_direction := 1.0 if is_equal_approx(corner.y, rect.position.y) else -1.0
		draw_line(corner, corner + Vector2(length * horizontal_direction, 0), Color(color, 0.72), 2.0)
		draw_line(corner, corner + Vector2(0, length * vertical_direction), Color(color, 0.72), 2.0)
