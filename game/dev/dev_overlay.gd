# Autoload "DevOverlay": a developer panel over any running facility
# (debug builds only; does nothing until a scene calls Facility.start_session).
#
# Facility time only moves when the player acts, so the dev keys stand in
# for player actions:
#   F1        show / hide
#   F5        one tick (0.1 facility s)
#   F6        spend 1 minute (like reading a dialogue line)   Shift: 1 hour
#   F7        spend 15 minutes (like a longer task)
#   F8        forget the save: next session starts a new facility
extends CanvasLayer

const LOG_LINES := 16

var panel: PanelContainer
var label: Label


func _ready() -> void:
	layer = 100
	panel = PanelContainer.new()
	panel.position = Vector2(12, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	panel.add_child(label)
	panel.visible = false


func _process(_delta: float) -> void:
	if panel.visible:
		label.text = _describe()


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not Facility.running:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:
			panel.visible = not panel.visible
		KEY_F5:
			Facility.spend(FacilitySim.TICK, "dev: one tick")
		KEY_F6:
			if event.shift_pressed:
				Facility.spend(3600.0, "dev: +1 hour")
			else:
				Facility.spend(60.0, "dev: +1 minute")
		KEY_F7:
			Facility.spend(900.0, "dev: +15 minutes")
		KEY_F8:
			Facility.wipe_save(Facility.save_path)
			Facility.sim.note("dev", "Save wiped: next session starts a new facility")
		_:
			return
	get_viewport().set_input_as_handled()


func _describe() -> String:
	if not Facility.running:
		return "Facility not running"
	var sim: FacilitySim = Facility.sim
	var lines := PackedStringArray()
	lines.append("FACILITY  %s   tick %d   (time only moves when the player acts)" % [
		FacilitySim.format_time(sim.time()), sim.tick])
	lines.append("systems: %s" % ", ".join(sim.system_ids()))
	lines.append("")
	lines.append("next events (%d booked):" % sim.scheduler.size())
	for e in sim.scheduler.peek(5):
		lines.append("  %s  %s  %s" % [FacilitySim.format_time(e.time), e.name, JSON.stringify(e.data)])
	lines.append("")
	lines.append("journal:")
	for e in sim.journal.tail(LOG_LINES):
		lines.append("  " + FacilityLog.format_entry(e))
	lines.append("")
	lines.append("F1 hide  F5 tick  F6 +1 min (Shift +1 h)  F7 +15 min  F8 wipe save")
	return "\n".join(lines)
