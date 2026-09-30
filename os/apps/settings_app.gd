# Settings: the corkLabs OS's own preferences (screen, start-up, pop-ups,
# windows). Nothing in here touches the facility. Saved in OSSettings.
class_name SettingsApp
extends OSApp

const SCALES := [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]


func _init() -> void:
	app_id = "settings"
	title = "Settings"
	default_size = Vector2(520, 460)
	icon_text = "SET"
	icon_color = OSTheme.TEXT_DIM


func build() -> void:
	_section("Screen")
	var scale_row := HBoxContainer.new()
	add_child(scale_row)
	var scale_label := OSTheme.label("Interface size", 14)
	scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_label)
	var scale := OptionButton.new()
	scale.focus_mode = Control.FOCUS_NONE
	var current: float = OSSettings.get_value("ui_scale")
	for i in SCALES.size():
		scale.add_item("%d%%" % roundi(SCALES[i] * 100.0), i)
		if is_equal_approx(SCALES[i], current):
			scale.select(i)
	scale.item_selected.connect(func(i: int):
		OSSettings.set_value("ui_scale", SCALES[i])
		_apply())
	scale_row.add_child(scale)
	_check("Fullscreen", "fullscreen", "")

	_section("Start-up")
	_check("Boot screen", "boot_animation", "The start-up text before the login screen")
	_check("Reopen my windows at log on", "restore_windows", "Windows come back where you left them")

	_section("Pop-up notifications")
	_check("Alarms", "toast_alarm", "")
	_check("Shift reports", "toast_report", "")
	add_child(OSTheme.label("Everything still goes to the notification centre (click the clock).", 12, OSTheme.TEXT_DIM))

	_section("Camera sound")
	_check("Mute camera feeds", "feed_muted", "Same as the Mute button in Cameras")
	_slider("Feed volume (everything heard through a camera)", "feed_volume", func(v: float): FeedAudio.set_volume(v))
	_check("Robot voices (heard while a robot is on camera)", "voices", "")
	_slider("Voice volume", "voice_volume", func(v: float): OSSettings.set_value("voice_volume", v))

	_section("Windows")
	add_child(button_row([
		["Forget window layout", func():
			OSSettings.set_value("windows", {})],
	]))


func _slider(text: String, key: String, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	add_child(row)
	var l := OSTheme.label(text, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var s := HSlider.new()
	s.custom_minimum_size.x = 180
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(OSSettings.get_value(key))
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	row.add_child(s)
	return s


func _section(text: String) -> void:
	var l := OSTheme.label(text.to_upper(), 12, OSTheme.ACCENT)
	add_child(l)


func _check(text: String, key: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(OSSettings.get_value(key))
	c.toggled.connect(func(on: bool):
		OSSettings.set_value(key, on)
		_apply())
	add_child(c)
	return c


func _apply() -> void:
	if desktop and desktop.has_method("apply_settings"):
		desktop.apply_settings()
