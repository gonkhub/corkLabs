# Coloured stretches of text in the Notes app: [start, end, colour] ranges
# over the page's text, drawn by the TextEdit's syntax highlighter, and kept
# on the right words as the page is edited (shift()).
class_name NoteColors
extends SyntaxHighlighter

const INK := Color("2b2616")

## [[start, end, "rrggbb"]...], sorted, not overlapping.
var marks: Array = []
var _line_starts := PackedInt32Array([0])
var _line_lengths := PackedInt32Array([0])


func update_lines(text: String) -> void:
	_line_starts = PackedInt32Array()
	_line_lengths = PackedInt32Array()
	var at := 0
	for line in text.split("\n"):
		_line_starts.append(at)
		_line_lengths.append(line.length())
		at += line.length() + 1


## Colours [a, b) (a transparent colour clears it).
func paint(a: int, b: int, c: Color) -> void:
	if b <= a:
		return
	var out: Array = []
	for m in marks:
		var s := int(m[0])
		var e := int(m[1])
		if e <= a or s >= b:
			out.append(m)
			continue
		if s < a:
			out.append([s, a, m[2]])
		if e > b:
			out.append([b, e, m[2]])
	if c.a > 0.0:
		out.append([a, b, c.to_html(false)])
	out.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	marks = out


## The text changed: [from, old_end) became `inserted` characters.
func shift(from: int, old_end: int, inserted: int) -> void:
	var delta := inserted - (old_end - from)
	var out: Array = []
	for m in marks:
		var s := _map(int(m[0]), from, old_end, delta, inserted)
		var e := _map(int(m[1]), from, old_end, delta, inserted)
		if e > s:
			out.append([s, e, m[2]])
	marks = out


static func _map(pos: int, from: int, old_end: int, delta: int, inserted: int) -> int:
	if pos <= from:
		return pos
	if pos >= old_end:
		return pos + delta
	return from + inserted   # inside the replaced stretch: collapses to its end


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var out := {0: {"color": INK}}
	if line >= _line_starts.size():
		return out
	var ls := _line_starts[line]
	var le := ls + _line_lengths[line]
	for m in marks:
		var s := int(m[0])
		var e := int(m[1])
		if e <= ls or s >= le:
			continue
		out[maxi(s, ls) - ls] = {"color": Color(str(m[2]))}
		if e < le:
			out[e - ls] = {"color": INK}
	return out
