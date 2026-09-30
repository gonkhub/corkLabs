# The corkLabs OS look: dark teal-grey panels, mint accents, amber for
# warnings, red for alarms. Built in code so it's easy to tweak: change a
# colour here and every window follows.
class_name OSTheme
extends RefCounted

const BG := Color("0c1517")
const BG2 := Color("132226")
const PANEL := Color("172327")
const PANEL_LIGHT := Color("1e2e33")
const TITLE := Color("223439")
const TITLE_FOCUS := Color("2b4a50")
const LINE := Color("35514f")
const TEXT := Color("d5e6df")
const TEXT_DIM := Color("7f9993")
const ACCENT := Color("5fd3a8")
const WARN := Color("f0b447")
const ALARM := Color("ff5a4a")
const INFO := Color("7fb8ff")

## Journal category -> colour (log app, messages, toasts).
const CATEGORY_COLORS := {
	"alarm": ALARM, "report": INFO, "work": Color("a9c7bf"), "plant": ACCENT,
	"supervisor": WARN, "shift": INFO, "facility": TEXT_DIM, "time": TEXT_DIM, "dev": TEXT_DIM,
}

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 14
	for type in ["Label", "Button", "CheckBox", "MenuButton", "LineEdit", "Tree", "ItemList", "RichTextLabel", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", Mono.font())
	t.set_font_size("normal_font_size", "RichTextLabel", 13)

	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE))

	for type in ["Button", "MenuButton"]:
		t.set_stylebox("normal", type, box(PANEL_LIGHT, LINE, 4, 8, 4))
		t.set_stylebox("hover", type, box(TITLE_FOCUS, ACCENT, 4, 8, 4))
		t.set_stylebox("pressed", type, box(ACCENT.darkened(0.55), ACCENT, 4, 8, 4))
		t.set_stylebox("disabled", type, box(PANEL, PANEL_LIGHT, 4, 8, 4))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_DIM.darkened(0.3))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	var bg := box(BG2, LINE, 2)
	var fill := box(ACCENT.darkened(0.2), Color(0, 0, 0, 0), 2)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 11)

	t.set_stylebox("panel", "Tree", box(BG2, LINE, 2, 4, 4))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", box(TITLE_FOCUS, ACCENT, 2))
	t.set_stylebox("selected_focus", "Tree", box(TITLE_FOCUS, ACCENT, 2))
	t.set_stylebox("title_button_normal", "Tree", box(TITLE, LINE, 0, 6, 3))
	t.set_stylebox("title_button_hover", "Tree", box(TITLE_FOCUS, LINE, 0, 6, 3))
	t.set_stylebox("title_button_pressed", "Tree", box(TITLE_FOCUS, LINE, 0, 6, 3))
	t.set_color("title_button_color", "Tree", TEXT_DIM)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("guide_color", "Tree", Color(0, 0, 0, 0))
	t.set_font("font", "Tree", Mono.font())
	t.set_font_size("font_size", "Tree", 13)
	t.set_constant("v_separation", "Tree", 3)

	t.set_stylebox("panel", "ItemList", box(BG2, LINE, 2, 4, 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", box(TITLE_FOCUS, ACCENT, 2))
	t.set_stylebox("selected_focus", "ItemList", box(TITLE_FOCUS, ACCENT, 2))
	t.set_stylebox("normal", "RichTextLabel", box(BG2, LINE, 2, 8, 6))
	t.set_stylebox("normal", "LineEdit", box(BG2, LINE, 2, 6, 4))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, LINE, 4, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(TITLE_FOCUS, Color(0, 0, 0, 0), 2))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_LIGHT, ACCENT, 3, 8, 5))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("grabber_area", "VScrollBar", box(LINE, Color(0, 0, 0, 0), 3))
	t.set_stylebox("grabber", "VScrollBar", box(LINE, Color(0, 0, 0, 0), 3))
	t.set_stylebox("scroll", "VScrollBar", box(BG, Color(0, 0, 0, 0), 3))
	_theme = t
	return t


static func box(fill: Color, border: Color, radius := 4, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func category_color(cat: String) -> Color:
	if CATEGORY_COLORS.has(cat):
		return CATEGORY_COLORS[cat]
	return Color("c9b7ff")   # robots


static func mono_label(text := "", size := 13, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Mono.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func label(text := "", size := 14, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A ProgressBar coloured by value (green, amber below `warn`, red below `bad`).
static func bar(value: float, warn := 0.5, bad := 0.25) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(120, 16)
	b.max_value = 1.0
	b.step = 0.001
	b.show_percentage = false
	set_bar(b, value, warn, bad)
	return b


static func set_bar(b: ProgressBar, value: float, warn := 0.5, bad := 0.25) -> void:
	b.value = value
	var c := ACCENT if value >= warn else (WARN if value >= bad else ALARM)
	var fill := b.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if fill and fill.bg_color != c.darkened(0.2):
		fill.bg_color = c.darkened(0.2)
		b.add_theme_stylebox_override("fill", fill)
