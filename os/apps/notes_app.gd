# Notes: the desk's notepad. Whatever's written here stays on the desk, not
# in the facility: it survives logging off, retrying a shift, even starting
# over on a new save (it lives in OSSettings), and corporate never reads it.
# A good place to keep a password, a serial number, the time something
# happens. Somebody else already has: the notepad came with notes in it.
#
#   Pages        a page list; + adds one, rename, delete.
#   Find         Ctrl+F: searches every page; Enter / F3 for the next match.
#   Colour       select some text, click a colour: it stays that colour as you
#                edit around it (Clear takes it off).
#   Font, size   per page: typewriter, plain or bold, 10-28.
#
# Writing costs no facility time.
class_name NotesApp
extends OSApp

const PAPER := Color("f5e6a8")
const INK := Color("2b2616")
const COLORS := [Color("c0392b"), Color("1f5fbf"), Color("2e8b57"), Color("8e44ad"), Color("d35400")]
const FONTS := ["Typewriter", "Plain", "Bold"]

var edit: TextEdit
var pages: Array = []          # [{"title", "text", "font", "size", "marks": [[start, end, color html]...]}]
var current := 0
var page_pick: OptionButton
var font_pick: OptionButton
var size_pick: SpinBox
var find_bar: HBoxContainer
var find_box: LineEdit
var find_count: Label
var _highlighter: NoteColors
var _old_text := ""
var _dirty := 0.0
var _matches: Array = []       # [[page, start, end]]
var _match_i := -1
var _switching := false
var _shown := -1               # the page that's in the editor (-1: none yet)


func _init() -> void:
	app_id = "notes"
	title = "Notes"
	default_size = Vector2(620, 480)
	icon_text = "TXT"
	icon_color = PAPER


func build() -> void:
	_load()
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 4)
	add_child(bar)
	page_pick = OptionButton.new()
	page_pick.focus_mode = Control.FOCUS_NONE
	page_pick.item_selected.connect(func(i: int): _open_page(i))
	bar.add_child(page_pick)
	_button(bar, "+ Page", "A new page", _add_page)
	_button(bar, "Rename", "Rename this page (its first line becomes the name)", _rename_page)
	_button(bar, "Delete", "Delete this page", _delete_page)
	bar.add_child(VSeparator.new())
	font_pick = OptionButton.new()
	font_pick.focus_mode = Control.FOCUS_NONE
	for f in FONTS:
		font_pick.add_item(f)
	font_pick.item_selected.connect(func(i: int):
		pages[current].font = FONTS[i]
		_apply_page_style()
		_dirty = 0.5)
	bar.add_child(font_pick)
	size_pick = SpinBox.new()
	size_pick.min_value = 10
	size_pick.max_value = 28
	size_pick.value_changed.connect(func(v: float):
		if _switching:
			return
		pages[current].size = int(v)
		_apply_page_style()
		_dirty = 0.5)
	bar.add_child(size_pick)
	bar.add_child(VSeparator.new())
	for c in COLORS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = "Colour the selected text"
		swatch.add_theme_stylebox_override("normal", OSTheme.box(c, c.darkened(0.3), 3, 0, 0))
		swatch.add_theme_stylebox_override("hover", OSTheme.box(c.lightened(0.2), c, 3, 0, 0))
		var col: Color = c
		swatch.pressed.connect(func(): color_selection(col))
		bar.add_child(swatch)
	_button(bar, "Clear", "Take the colour off the selected text", func(): color_selection(INK))

	find_bar = HBoxContainer.new()
	find_bar.visible = false
	add_child(find_bar)
	find_bar.add_child(OSTheme.label("Find:", 12, OSTheme.TEXT_DIM))
	find_box = LineEdit.new()
	find_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_box.placeholder_text = "search every page (Enter: next)"
	find_box.text_changed.connect(func(_t: String): find(find_box.text))
	find_box.text_submitted.connect(func(_t: String): find_next())
	find_bar.add_child(find_box)
	find_count = OSTheme.label("", 12, OSTheme.TEXT_DIM)
	find_bar.add_child(find_count)
	_button(find_bar, "Next", "Next match (F3)", find_next)
	_button(find_bar, "x", "Close (Esc)", func(): find_bar.visible = false)

	edit = TextEdit.new()
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.add_theme_color_override("font_color", INK)
	edit.add_theme_color_override("caret_color", INK)
	edit.add_theme_color_override("selection_color", Color(0.3, 0.45, 0.8, 0.35))
	edit.add_theme_stylebox_override("normal", OSTheme.box(PAPER, Color("c9b56a"), 2, 12, 10))
	edit.add_theme_stylebox_override("focus", OSTheme.box(PAPER, Color("c9b56a"), 2, 12, 10))
	_highlighter = NoteColors.new()
	edit.syntax_highlighter = _highlighter
	edit.text_changed.connect(_on_text_changed)
	add_child(edit)
	add_child(OSTheme.label("Notes stay on the desk, whatever happens to the facility. Ctrl+F finds; select text and click a colour.", 11, OSTheme.TEXT_DIM))
	_fill_pages()
	_open_page(current)


# --- Pages ------------------------------------------------------------------------------

func _load() -> void:
	var book = OSSettings.get_value("notebook")
	pages = []
	if book is Dictionary and (book.get("pages", []) as Array).size() > 0:
		for p in book.pages:
			pages.append({"title": str(p.get("title", "Page")), "text": str(p.get("text", "")), "font": str(p.get("font", "Typewriter")),
				"size": int(p.get("size", 14)), "marks": (p.get("marks", []) as Array).duplicate(true)})
		current = clampi(int(book.get("current", 0)), 0, pages.size() - 1)
	else:
		# The old one-page notepad (and what was left on it).
		pages.append({"title": "Notes", "text": str(OSSettings.get_value("notes")), "font": "Typewriter", "size": 14, "marks": []})
		current = 0


func save() -> void:
	_store_page()
	OSSettings.set_value("notebook", {"pages": pages.duplicate(true), "current": current})
	OSSettings.set_value("notes", all_text())   # (the plain text of every page, for anything that reads the old notepad)


## Every page's text, one after another.
func all_text() -> String:
	return "\n\n".join(pages.map(func(p): return str(p.text)))


func _store_page() -> void:
	if edit and _shown == current and current < pages.size():
		pages[current].text = edit.text
		pages[current].marks = _highlighter.marks.duplicate(true)


func _fill_pages() -> void:
	page_pick.clear()
	for i in pages.size():
		page_pick.add_item(str(pages[i].title), i)
	page_pick.select(current)


func _open_page(i: int) -> void:
	_store_page()
	current = clampi(i, 0, pages.size() - 1)
	_switching = true
	var p: Dictionary = pages[current]
	_highlighter.marks = (p.marks as Array).duplicate(true)
	edit.text = str(p.text)
	_shown = current
	_old_text = edit.text
	_highlighter.update_lines(edit.text)
	edit.syntax_highlighter = null   # (re-set: the cache is per text)
	edit.syntax_highlighter = _highlighter
	font_pick.select(maxi(FONTS.find(str(p.font)), 0))
	size_pick.value = int(p.size)
	_apply_page_style()
	page_pick.select(current)
	_switching = false


func _apply_page_style() -> void:
	var p: Dictionary = pages[current]
	var font: Font = Mono.font()
	match str(p.font):
		"Plain":
			font = ThemeDB.fallback_font
		"Bold":
			var f := FontVariation.new()
			f.base_font = ThemeDB.fallback_font
			f.variation_embolden = 0.9
			font = f
	edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override("font_size", int(p.size))


func _add_page() -> void:
	_store_page()
	pages.append({"title": "Page %d" % (pages.size() + 1), "text": "", "font": "Typewriter", "size": 14, "marks": []})
	_fill_pages()
	_open_page(pages.size() - 1)
	save()


func _rename_page() -> void:
	var first := edit.text.get_slice("\n", 0).strip_edges().left(28)
	pages[current].title = first if not first.is_empty() else "Page %d" % (current + 1)
	_fill_pages()
	save()


func _delete_page() -> void:
	if pages.size() <= 1:
		edit.text = ""
		_highlighter.marks.clear()
		_on_text_changed()
		return
	pages.remove_at(current)
	_shown = -1
	current = mini(current, pages.size() - 1)
	_fill_pages()
	_switching = true
	_open_page(current)
	save()


# --- Colour -------------------------------------------------------------------------------

## Colours the selected text (INK takes the colour off).
func color_selection(c: Color) -> void:
	if not edit.has_selection():
		return
	var a := _offset(edit.get_selection_from_line(), edit.get_selection_from_column())
	var b := _offset(edit.get_selection_to_line(), edit.get_selection_to_column())
	_highlighter.paint(a, b, c if c != INK else Color(0, 0, 0, 0))
	edit.syntax_highlighter = null
	edit.syntax_highlighter = _highlighter
	_dirty = 0.5


func _offset(line: int, col: int) -> int:
	var n := 0
	for i in line:
		n += edit.get_line(i).length() + 1
	return n + col


# Keeps the colours on the text as it's edited: the changed stretch is found
# by the common start and end of the old and new text.
func _on_text_changed() -> void:
	var now := edit.text
	var p := 0
	var limit := mini(_old_text.length(), now.length())
	while p < limit and _old_text[p] == now[p]:
		p += 1
	var s := 0
	while s < limit - p and _old_text[_old_text.length() - 1 - s] == now[now.length() - 1 - s]:
		s += 1
	_highlighter.shift(p, _old_text.length() - s, now.length() - s - p)
	_old_text = now
	_highlighter.update_lines(now)
	if not _switching:
		_dirty = 1.0


# --- Find --------------------------------------------------------------------------------

## Finds `word` on every page. Returns how many matches.
func find(word: String) -> int:
	_store_page()
	_matches.clear()
	_match_i = -1
	var w := word.to_lower()
	if not w.is_empty():
		for i in pages.size():
			var t := str(pages[i].text).to_lower()
			var at := t.find(w)
			while at >= 0:
				_matches.append([i, at, at + w.length()])
				at = t.find(w, at + 1)
	find_count.text = ("%d found" % _matches.size()) if not w.is_empty() else ""
	return _matches.size()


## Goes to the next match (switching page if it has to).
func find_next() -> void:
	if _matches.is_empty():
		find(find_box.text)
		if _matches.is_empty():
			return
	_match_i = (_match_i + 1) % _matches.size()
	var m: Array = _matches[_match_i]
	if int(m[0]) != current:
		_open_page(int(m[0]))
	var from := _line_col(int(m[1]))
	var to := _line_col(int(m[2]))
	edit.select(from.x, from.y, to.x, to.y)
	edit.set_caret_line(to.x)
	edit.set_caret_column(to.y)
	edit.center_viewport_to_caret()
	find_count.text = "%d of %d" % [_match_i + 1, _matches.size()]


func _line_col(offset: int) -> Vector2i:
	var n := 0
	for i in edit.get_line_count():
		var ll := edit.get_line(i).length()
		if offset <= n + ll:
			return Vector2i(i, offset - n)
		n += ll + 1
	return Vector2i(edit.get_line_count() - 1, 0)


# --- Keys, saving -------------------------------------------------------------------------

func key_input(event: InputEventKey) -> bool:
	if event.ctrl_pressed and event.keycode == KEY_F:
		find_bar.visible = true
		find_box.grab_focus()
		find_box.select_all()
		return true
	if event.keycode == KEY_F3:
		find_next()
		return true
	if event.keycode == KEY_ESCAPE and find_bar.visible:
		find_bar.visible = false
		edit.grab_focus()
		return true
	return (edit != null and edit.has_focus()) or (find_box != null and find_box.has_focus())


func _process(delta: float) -> void:
	# Save a second after the last change.
	if _dirty > 0.0:
		_dirty -= delta
		if _dirty <= 0.0:
			save()


func _button(row: Container, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	row.add_child(b)
	return b


func _exit_tree() -> void:
	if edit and _dirty > 0.0:
		save()
