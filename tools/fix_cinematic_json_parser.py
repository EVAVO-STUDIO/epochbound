from pathlib import Path

path = Path("addons/epochbound_cinematic_studio/cinematic_studio.gd")
text = path.read_text(encoding="utf-8")
old = '''\t\tvar parsed: Variant = JSON.parse_string(line)
\t\tif typeof(parsed) != TYPE_DICTIONARY:
\t\t\terrors.append("%s line %d must be one JSON object." % [label, line_number])
\t\telse:
\t\t\tentries.append(parsed)
'''
new = '''\t\tvar parser := JSON.new()
\t\tvar parse_error := parser.parse(line)
\t\tif parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
\t\t\terrors.append("%s line %d must be one valid JSON object." % [label, line_number])
\t\telse:
\t\t\tentries.append(parser.data)
'''
if text.count(old) != 1:
    raise SystemExit(f"Expected one cinematic JSON parser block, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
Path("tools/fix_cinematic_json_parser.py").unlink()
