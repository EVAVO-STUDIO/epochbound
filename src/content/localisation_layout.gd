@tool
extends RefCounted

# Deterministic text fitting for Epochbound's fixed 640 by 360 presentation.
# The utility measures the real Godot Font resource, shrinks only within an
# authored size range, wraps on stable word boundaries, and uses one visible
# ellipsis marker when a bounded surface still cannot contain the full copy.

const ELLIPSIS := "…"
const WIDTH_EPSILON := 0.5
const MIN_FONT_SIZE := 4
const MAX_FONT_SIZE := 96
const MAX_WRAP_LINES := 16


static func localisation_layout_contract_ok() -> bool:
	return (
		not ELLIPSIS.is_empty()
		and WIDTH_EPSILON > 0.0
		and MIN_FONT_SIZE >= 4
		and MAX_FONT_SIZE >= MIN_FONT_SIZE
		and MAX_WRAP_LINES >= 4
		and MAX_WRAP_LINES <= 32
	)


static func fit_single_line(
	font: Font,
	text: String,
	preferred_size: int,
	minimum_size: int,
	max_width: float
) -> Dictionary:
	var normalized := single_line(text)
	var preferred := clampi(preferred_size, MIN_FONT_SIZE, MAX_FONT_SIZE)
	var minimum := clampi(minimum_size, MIN_FONT_SIZE, preferred)
	var output := {
		"ok": false,
		"text": "",
		"font_size": minimum,
		"width": 0.0,
		"truncated": false,
		"errors": []
	}
	if font == null:
		(output["errors"] as Array).append("A valid Font is required for localisation layout measurement.")
		return output
	if max_width <= 0.0:
		(output["errors"] as Array).append("The localisation layout width must be greater than zero.")
		return output
	if normalized.is_empty():
		output["ok"] = true
		return output
	for size in range(preferred, minimum - 1, -1):
		var width := string_width(font, normalized, size)
		if width <= max_width + WIDTH_EPSILON:
			output["ok"] = true
			output["text"] = normalized
			output["font_size"] = size
			output["width"] = width
			return output
	var clipped := ellipsize(font, normalized, minimum, max_width)
	var clipped_width := string_width(font, clipped, minimum) if not clipped.is_empty() else 0.0
	output["ok"] = not clipped.is_empty() and clipped_width <= max_width + WIDTH_EPSILON
	output["text"] = clipped
	output["font_size"] = minimum
	output["width"] = clipped_width
	output["truncated"] = clipped != normalized
	if not bool(output["ok"]):
		(output["errors"] as Array).append("The minimum-size text cannot fit the declared width.")
	return output


static func fit_block(
	font: Font,
	text: String,
	preferred_size: int,
	minimum_size: int,
	max_width: float,
	max_lines: int,
	max_height: float,
	line_gap: float = 4.0
) -> Dictionary:
	var preferred := clampi(preferred_size, MIN_FONT_SIZE, MAX_FONT_SIZE)
	var minimum := clampi(minimum_size, MIN_FONT_SIZE, preferred)
	var line_limit := clampi(max_lines, 1, MAX_WRAP_LINES)
	var gap := maxf(0.0, line_gap)
	var output := {
		"ok": false,
		"lines": [],
		"font_size": minimum,
		"width": 0.0,
		"height": 0.0,
		"truncated": false,
		"errors": []
	}
	if font == null:
		(output["errors"] as Array).append("A valid Font is required for localisation block measurement.")
		return output
	if max_width <= 0.0 or max_height <= 0.0:
		(output["errors"] as Array).append("Localisation block dimensions must be greater than zero.")
		return output
	if max_lines <= 0:
		(output["errors"] as Array).append("The localisation block line limit must be greater than zero.")
		return output
	var normalized := block_text(text)
	if normalized.is_empty():
		output["ok"] = true
		return output
	for size in range(preferred, minimum - 1, -1):
		var lines := wrap_text(font, normalized, size, max_width)
		var height := block_height(lines, size, gap)
		if lines.size() <= line_limit and height <= max_height + WIDTH_EPSILON and lines_fit(font, lines, size, max_width):
			output["ok"] = true
			output["lines"] = lines
			output["font_size"] = size
			output["width"] = max_line_width(font, lines, size)
			output["height"] = height
			return output

	var minimum_lines := wrap_text(font, normalized, minimum, max_width)
	if float(minimum) > max_height + WIDTH_EPSILON:
		(output["errors"] as Array).append("The minimum font size exceeds the declared block height.")
		return output
	var height_limit := maxi(1, int(floor((max_height + gap) / (float(minimum) + gap))))
	var allowed_lines := mini(line_limit, height_limit)
	var visible: Array[String] = []
	for index in range(mini(allowed_lines, minimum_lines.size())):
		visible.append(minimum_lines[index])
	var omitted := minimum_lines.size() > visible.size()
	if visible.is_empty():
		visible.append(ellipsize(font, normalized, minimum, max_width))
		omitted = true
	if omitted:
		visible[visible.size() - 1] = line_with_ellipsis(font, visible[visible.size() - 1], minimum, max_width)
	var final_height := block_height(visible, minimum, gap)
	var final_width := max_line_width(font, visible, minimum)
	output["ok"] = (
		final_height <= max_height + WIDTH_EPSILON
		and final_width <= max_width + WIDTH_EPSILON
		and lines_fit(font, visible, minimum, max_width)
	)
	output["lines"] = visible
	output["font_size"] = minimum
	output["width"] = final_width
	output["height"] = final_height
	output["truncated"] = omitted
	if not bool(output["ok"]):
		(output["errors"] as Array).append("The minimum-size block cannot fit the declared bounds.")
	return output


static func wrap_text(font: Font, text: String, font_size: int, max_width: float) -> Array[String]:
	var output: Array[String] = []
	if font == null or max_width <= 0.0:
		return output
	var paragraphs := block_text(text).split("\n", true)
	for paragraph_value in paragraphs:
		var paragraph := str(paragraph_value).strip_edges()
		if paragraph.is_empty():
			output.append("")
			continue
		var words := paragraph.split(" ", false)
		var current := ""
		for word_value in words:
			var word := str(word_value)
			if word.is_empty():
				continue
			var candidate := word if current.is_empty() else "%s %s" % [current, word]
			if string_width(font, candidate, font_size) <= max_width + WIDTH_EPSILON:
				current = candidate
				continue
			if not current.is_empty():
				output.append(current)
				current = ""
			if string_width(font, word, font_size) <= max_width + WIDTH_EPSILON:
				current = word
				continue
			var pieces := split_long_token(font, word, font_size, max_width)
			for piece_index in range(pieces.size()):
				var piece := pieces[piece_index]
				if piece_index == pieces.size() - 1:
					current = piece
				else:
					output.append(piece)
		if not current.is_empty():
			output.append(current)
	return output


static func split_long_token(font: Font, token: String, font_size: int, max_width: float) -> Array[String]:
	var output: Array[String] = []
	var current := ""
	for index in range(token.length()):
		var character := token.substr(index, 1)
		var candidate := current + character
		if not current.is_empty() and string_width(font, candidate, font_size) > max_width + WIDTH_EPSILON:
			output.append(current)
			current = character
		else:
			current = candidate
	if not current.is_empty():
		output.append(current)
	return output


static func ellipsize(font: Font, text: String, font_size: int, max_width: float) -> String:
	var normalized := single_line(text)
	if normalized.is_empty() or font == null or max_width <= 0.0:
		return ""
	if string_width(font, normalized, font_size) <= max_width + WIDTH_EPSILON:
		return normalized
	if string_width(font, ELLIPSIS, font_size) > max_width + WIDTH_EPSILON:
		return ""
	for length in range(normalized.length(), -1, -1):
		var prefix := normalized.substr(0, length).strip_edges()
		var candidate := ELLIPSIS if prefix.is_empty() else prefix + ELLIPSIS
		if string_width(font, candidate, font_size) <= max_width + WIDTH_EPSILON:
			return candidate
	return ""


static func line_with_ellipsis(font: Font, text: String, font_size: int, max_width: float) -> String:
	var normalized := single_line(text)
	if normalized.ends_with(ELLIPSIS):
		return normalized
	var direct := normalized + ELLIPSIS
	if string_width(font, direct, font_size) <= max_width + WIDTH_EPSILON:
		return direct
	return ellipsize(font, normalized, font_size, max_width)


static func lines_fit(font: Font, lines_value: Variant, font_size: int, max_width: float) -> bool:
	if font == null or typeof(lines_value) != TYPE_ARRAY or max_width <= 0.0:
		return false
	for line_value in lines_value:
		if string_width(font, str(line_value), font_size) > max_width + WIDTH_EPSILON:
			return false
	return true


static func max_line_width(font: Font, lines_value: Variant, font_size: int) -> float:
	if font == null or typeof(lines_value) != TYPE_ARRAY:
		return 0.0
	var width := 0.0
	for line_value in lines_value:
		width = maxf(width, string_width(font, str(line_value), font_size))
	return width


static func block_height(lines_value: Variant, font_size: int, line_gap: float = 4.0) -> float:
	if typeof(lines_value) != TYPE_ARRAY:
		return 0.0
	var count := (lines_value as Array).size()
	if count <= 0:
		return 0.0
	return float(count * font_size) + float(maxi(0, count - 1)) * maxf(0.0, line_gap)


static func string_width(font: Font, text: String, font_size: int) -> float:
	if font == null or text.is_empty():
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


static func single_line(text: String) -> String:
	return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()


static func block_text(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n").replace("\t", " ").strip_edges()
