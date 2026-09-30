# Handbook: the supervisor's manual. How the facility, the robots and the
# apps work, in plain words. (In-world it's the corkLabs onboarding document;
# for us it's the tutorial until there is a real one.)
class_name HandbookApp
extends OSApp

const SECTIONS := [
	["Your job", """You supervise the maintenance units of this compound from this terminal. The units keep the plant running: the pods, the coolant loop, the power relay and the bays.

Keep [b]throughput[/b] up (the taskbar shows it). Throughput is the pods' average sync."""],
	["Facility time", """Facility time only moves when you do something. Giving an order or changing a priority takes 2 minutes. [b]Wait[/b] on the taskbar lets time pass while you watch; an alarm or a shift report stops the wait.

Looking is free: opening apps and moving cameras costs no time.

Log off whenever you like. The facility is put on hold and resumes at the same minute when you log back on."""],
	["The units", """[b]Hauler[/b] is built for heavy work (debris, coolant leaks, refitting parts). Slow, strong, steady.
[b]Tinker[/b] is built for precise work (pods, fuses, repairs at the workbench). Quick, curious, restless.

Each unit decides for itself what to do next, weighing up every job it can reach. The [b]Units[/b] app shows what each one is weighing up and why.

Units need [b]power[/b] (they recharge at their dock) and [b]purpose[/b]: standing idle makes them restless, then uneasy, and they start to wander looking for work."""],
	["Orders", """An order is a strong nudge, not a command. Usually a unit says "On it." But a unit low on power recharges first, a unit won't take work it's hopeless at, and an uneasy unit finds it hard to stand still.

Give orders from [b]Work Orders[/b] (assign a job), [b]Units[/b] (recharge, stand by, cancel) or the [b]Terminal[/b]. Answers arrive in [b]Messages[/b]."""],
	["The plant", """Pods lose sync over time and need recalibrating. Filters clog. Coolant pipes leak. The relay fuse blows. Debris falls in the bays.

Problems chain: an unclamped leak drains coolant, the facility runs hot, and the pods drift faster. A blown fuse makes the docks charge slowly. The [b]Plant[/b] app shows every device; the [b]ALARM[/b] light on the taskbar blinks while anything is broken."""],
	["Apps", """[b]Cameras[/b]: watch the floor. Drag to pan and tilt, scroll to zoom, double-click to reset. Grid view shows every camera.
[b]Units[/b]: each unit's state and thinking. [b]Work Orders[/b]: the job board.
[b]Plant[/b]: the facility's vital signs. [b]Messages[/b]: what the units say to you.
[b]Facility Log[/b]: everything that happened. [b]Terminal[/b]: type commands (try [b]help[/b]).
[b]Settings[/b]: screen and notifications.

Windows: drag the title bar, drag to a screen edge to snap, double-click the title to maximise, right-click the desktop for more. Click the clock for your notifications."""],
]

var view: RichTextLabel
var index: ItemList


func _init() -> void:
	app_id = "handbook"
	title = "Handbook"
	default_size = Vector2(720, 480)
	icon_text = "?"
	icon_color = OSTheme.TEXT


func build() -> void:
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	index = ItemList.new()
	index.custom_minimum_size.x = 150
	for s in SECTIONS:
		index.add_item(s[0])
	index.item_selected.connect(show_section)
	split.add_child(index)
	view = RichTextLabel.new()
	view.bbcode_enabled = true
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_font_override("normal_font", get_theme_default_font())
	view.add_theme_font_size_override("normal_font_size", 15)
	view.add_theme_font_size_override("bold_font_size", 15)
	split.add_child(view)
	index.select(0)
	show_section(0)


func show_section(i: int) -> void:
	view.text = "[font_size=22][color=#%s]%s[/color][/font_size]\n\n%s" % [OSTheme.ACCENT.to_html(false), SECTIONS[i][0], SECTIONS[i][1]]


func save_state() -> Dictionary:
	var sel := index.get_selected_items()
	return {"section": sel[0] if sel.size() > 0 else 0}


func load_state(state: Dictionary) -> void:
	var i := clampi(int(state.get("section", 0)), 0, SECTIONS.size() - 1)
	index.select(i)
	show_section(i)
