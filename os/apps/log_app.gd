# Facility Log: the journal, everything that happened, with filters.
# Robots' decisions (with their scores and reasons) are all in here.
class_name LogApp
extends OSApp

## Filter name -> journal categories ([] = everything except time bookkeeping).
const FILTERS := [
	["All", []],
	["Alarms", ["alarm"]],
	["Robots", ["robots"]],
	["Work", ["work"]],
	["Plant", ["plant", "report"]],
	["You", ["supervisor"]],
]

var view: RichTextLabel
var filter := 0
var _mark := -1


func _init() -> void:
	app_id = "log"
	title = "Facility Log"
	default_size = Vector2(860, 440)
	icon_text = "LOG"
	icon_color = OSTheme.TEXT_DIM


func build() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var group := ButtonGroup.new()
	for i in FILTERS.size():
		var b := Button.new()
		b.text = FILTERS[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			filter = i
			_mark = -1
			refresh())
		row.add_child(b)
	view = RichTextLabel.new()
	view.bbcode_enabled = true
	view.scroll_following = true
	view.selection_enabled = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(view)


func refresh() -> void:
	if sim() == null or view == null:
		return
	var journal := sim().journal
	if journal.added == _mark:
		return
	_mark = journal.added
	var robots := {}
	for bot in FacilitySetup.robots(sim()):
		robots[bot.robot_id] = true
	var cats: Array = FILTERS[filter][1]
	var out := PackedStringArray()
	for e in journal.entries:
		var cat := str(e.cat)
		if cat == "time":
			continue
		if not cats.is_empty():
			var robot_hit: bool = cats.has("robots") and robots.has(cat)
			if not (cats.has(cat) or robot_hit):
				continue
		out.append("[color=#%s]%s[/color]  [color=#%s]%-10s[/color] %s" % [OSTheme.TEXT_DIM.to_html(false),
			FacilitySim.format_time(e.t), OSTheme.category_color(cat).to_html(false), cat, _escape(str(e.text))])
	view.text = "\n".join(out.slice(maxi(0, out.size() - 400)))


static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")
