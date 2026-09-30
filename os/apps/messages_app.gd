# Messages: a thread per robot (your orders and their answers, plus how
# they're doing: moods, power, stalls), and a Facility thread for alarms and
# shift reports. Built from the journal, so it's always in step with the sim.
# Talking *to* the robots (dialogue) will grow out of this.
class_name MessagesApp
extends OSApp

const STATUS_WORDS := ["feels", "power low", "OUT OF POWER", "charged to", "restarts", "online", "stand-by order lapsed"]

var threads: ItemList
var view: RichTextLabel
var thread_ids: Array[String] = []
var current := ""
var _mark := -1


func _init() -> void:
	app_id = "messages"
	title = "Messages"
	default_size = Vector2(720, 460)
	icon_text = "MSG"
	icon_color = Color("ff9ecb")


## A robot answering the supervisor (these become toasts).
static func is_message(e: Dictionary) -> bool:
	return str(e.text).contains(", to the supervisor: ")


## Just the words a robot said.
static func message_text(e: Dictionary) -> String:
	var t := str(e.text)
	var i := t.find(", to the supervisor: ")
	return t.substr(i + 21).trim_prefix("\"").trim_suffix("\"") if i >= 0 else t


func build() -> void:
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 160
	add_child(split)
	threads = ItemList.new()
	threads.custom_minimum_size.x = 150
	threads.item_selected.connect(func(i: int):
		current = thread_ids[i]
		_mark = -1
		refresh())
	split.add_child(threads)
	view = RichTextLabel.new()
	view.bbcode_enabled = true
	view.scroll_following = true
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(view)
	if sim():
		for bot in FacilitySetup.robots(sim()):
			thread_ids.append(bot.robot_id)
			threads.add_item(bot.display_name())
		thread_ids.append("facility")
		threads.add_item("Facility")
		current = thread_ids[0]
		threads.select(0)


func refresh() -> void:
	if sim() == null or view == null:
		return
	var journal := sim().journal
	if journal.added == _mark:
		return
	_mark = journal.added
	var names := {}
	for bot in FacilitySetup.robots(sim()):
		names[bot.display_name()] = bot.robot_id
	var out := PackedStringArray()
	for e in journal.entries:
		var line := _line(e, names)
		if not line.is_empty():
			out.append(line)
	view.text = "\n".join(out.slice(maxi(0, out.size() - 250)))


# One journal entry as a line in the current thread, or "" if it isn't part of it.
func _line(e: Dictionary, names: Dictionary) -> String:
	var cat := str(e.cat)
	var text := str(e.text).replace("[", "[lb]")
	var clock := FacilitySim.format_clock(e.t)
	var dim := OSTheme.TEXT_DIM.to_html(false)
	if current == "facility":
		if cat == "alarm":
			return "[color=#%s]%s[/color]  [color=#%s][b]%s[/b][/color]" % [dim, clock, OSTheme.ALARM.to_html(false), text]
		if cat == "report":
			return "[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [dim, clock, OSTheme.INFO.to_html(false), text]
		if cat == "shift":
			return "[color=#%s]%s  %s[/color]" % [dim, clock, text]
		return ""
	if cat == "supervisor":
		# "To Tinker: take job #3 ..."
		for n in names:
			if names[n] == current and text.begins_with("To %s:" % n):
				return "[right][color=#%s]%s[/color]  [color=#%s]You: %s[/color][/right]" % [dim, clock,
					OSTheme.WARN.to_html(false), text.substr(text.find(":") + 2)]
		return ""
	if cat != current:
		return ""
	var col := OSTheme.category_color(cat).to_html(false)
	if is_message(e):
		return "[color=#%s]%s[/color]  [color=#%s][b]%s:[/b][/color] %s" % [dim, clock, col, cat.capitalize(), message_text(e)]
	for w in STATUS_WORDS:
		if text.contains(w):
			return "[color=#%s][i]%s  %s[/i][/color]" % [dim, clock, text]
	return ""
