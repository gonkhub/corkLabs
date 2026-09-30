# corkHQ: corporate's permanent window. It sits in the top-right corner of
# the corkLabs OS, above every other window, and the player can't close it,
# minimise it, move it, resize it or mute it. Every new message chimes (at a
# fixed volume: the OS volume settings don't reach it), flashes and shakes.
#
# It shows CorkHQ's messages (the simulation side: game/corporate/cork_hq.gd):
# directives, shift reviews and grades, nagging, requisition confirmations
# and status, software approvals with install codes. The header judges you:
# your rating, budget, clearance and standing.
#
# The one way to quieten it: the maintenance account's "hqctl mute". While
# the link is suspended the panel goes dark and holds new messages; they all
# arrive at once when it comes back. Corporate notices at the next audit.
class_name CorkHQPanel
extends PanelContainer

const WIDTH := 400.0
const HEIGHT := 340.0
const MARGIN := 10.0
const FLASH_TIME := 2.5
const SHAKE_TIME := 0.45
const KIND_COLORS := {
	"directive": Color("e8e2d0"), "review": Color("f0b447"), "warning": Color("ff5a4a"),
	"order": Color("7fb8ff"), "software": Color("5fd3a8"), "notice": Color("c9d1cf"),
}
const RED := Color("c8322a")

var status: Label
var list: VBoxContainer
var chime: AudioStreamPlayer
var _style: StyleBoxFlat
var _mark := 0
var _flash := 0.0
var _shake := 0.0
var _home := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _suspended: Label


func _ready() -> void:
	name = "CorkHQ"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	_style = OSTheme.box(Color("1b1414"), RED, 4, 0, 0)
	_style.set_border_width_all(2)
	_style.shadow_color = Color(0, 0, 0, 0.6)
	_style.shadow_size = 14
	add_theme_stylebox_override("panel", _style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	# Title bar: no buttons. There is nothing you can do about this window.
	var bar := PanelContainer.new()
	var bar_style := OSTheme.box(RED.darkened(0.25), Color(0, 0, 0, 0), 2, 10, 4)
	bar_style.corner_radius_bottom_left = 0
	bar_style.corner_radius_bottom_right = 0
	bar.add_theme_stylebox_override("panel", bar_style)
	col.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var title := OSTheme.label("corkHQ", 16, Color.WHITE)
	row.add_child(title)
	var sub := OSTheme.label("  Corporate Liaison", 12, Color(1, 1, 1, 0.75))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sub)
	row.add_child(OSTheme.mono_label("● LIVE", 11, Color(1, 0.85, 0.8)))
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 8)
	col.add_child(body)
	var inner := VBoxContainer.new()
	body.add_child(inner)
	status = OSTheme.mono_label("", 12, Color("f0d9b5"))
	inner.add_child(status)
	inner.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	_suspended = OSTheme.mono_label("LINK SUSPENDED
(maintenance)", 18, Color(1, 0.4, 0.35, 0.8))
	_suspended.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_suspended.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_suspended.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_suspended.visible = false
	inner.add_child(_suspended)
	chime = AudioStreamPlayer.new()
	chime.stream = _make_chime()
	chime.volume_db = -4.0   # fixed: not tied to any OS setting
	chime.bus = FeedAudio.UI
	add_child(chime)
	_rng.randomize()
	get_viewport().size_changed.connect(_place)
	_place()


## Pinned to the top-right corner of the screen.
func _place() -> void:
	var area := get_parent_area_size() if get_parent() else Vector2(1600, 900)
	_home = Vector2(area.x - WIDTH - MARGIN, MARGIN)
	position = _home
	size = Vector2(WIDTH, HEIGHT)


func _process(delta: float) -> void:
	if not Facility.running:
		return
	var hq := Facility.sim.get_system("hq") as CorkHQ
	if hq == null:
		return
	var o := Facility.sim.get_system("oversight") as Oversight
	var muted := o != null and o.hq_muted(Facility.sim)
	_suspended.visible = muted
	list.get_parent().visible = not muted
	if hq.posted != _mark and not muted:
		_mark = hq.posted
		_rebuild(hq)
		_alert()
	_refresh_status(hq)
	# Flashing border and a shake after each new message.
	if _flash > 0.0:
		_flash -= delta
		_style.border_color = RED.lerp(Color.WHITE, 0.5 + 0.5 * sin(_flash * 20.0)) if _flash > 0.0 else RED
	if _shake > 0.0:
		_shake -= delta
		position = _home + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-2, 2)) * (_shake / SHAKE_TIME)
		if _shake <= 0.0:
			position = _home


# You get notified. You don't get a choice.
func _alert() -> void:
	chime.play()
	_flash = FLASH_TIME
	_shake = SHAKE_TIME


func _refresh_status(hq: CorkHQ) -> void:
	var req := Facility.sim.get_system("requisitions") as Requisitions
	var sw := Facility.sim.get_system("software") as SoftwareLibrary
	var o := Facility.sim.get_system("oversight") as Oversight
	status.text = "RATING %s   FUNDS %s cr   CLEARANCE %d" % [hq.grade if hq.grade != "" else "pending",
		_thousands(req.funds) if req else "?", sw.clearance if sw else 1]
	if o:
		status.text += "
STANDING %d/100%s" % [roundi(o.standing), "   WARNINGS %d" % o.strikes if o.strikes > 0 else ""]


## Redraws right away (after the link is suspended or restored).
func refresh_now() -> void:
	_process(0.0)


func _rebuild(hq: CorkHQ) -> void:
	for c in list.get_children():
		c.queue_free()
	var msgs := hq.messages.duplicate()
	msgs.reverse()   # newest first
	for m in msgs.slice(0, 30):
		list.add_child(_message(m))


func _message(m: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	var head := HBoxContainer.new()
	col.add_child(head)
	var who := OSTheme.label(str(m.sender).to_upper(), 11, KIND_COLORS.get(m.kind, Color.WHITE))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	head.add_child(OSTheme.mono_label(FacilitySim.format_clock(m.t), 11, OSTheme.TEXT_DIM))
	var text := OSTheme.label(str(m.text), 13, OSTheme.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = WIDTH - 40.0
	col.add_child(text)
	if not str(m.get("code", "")).is_empty():
		var code := OSTheme.mono_label("CODE  " + str(m.code), 16, Color("5fd3a8"))
		col.add_child(code)
	return col


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# A corporate two-tone "ding-dong", generated (a placeholder for real sound).
static func _make_chime() -> AudioStreamWAV:
	var rate := 22050
	var notes := [[988.0, 0.16], [740.0, 0.3]]
	var data := PackedByteArray()
	var total := 0
	for n in notes:
		total += int(rate * float(n[1]))
	data.resize(total * 2)
	var i := 0
	for n in notes:
		var count := int(rate * float(n[1]))
		for k in count:
			var t := float(k) / count
			var env := minf(t * 30.0, 1.0) * pow(1.0 - t, 1.2)
			var v := (sin(TAU * float(n[0]) * k / rate) + 0.3 * sin(TAU * float(n[0]) * 2.0 * k / rate)) * env * 0.4
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
			i += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
