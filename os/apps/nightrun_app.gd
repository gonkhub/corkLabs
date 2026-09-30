# NIGHT RUN v0.9, by R.M.: the game a former supervisor left in
# /opt/games. A cart on a rail in the dark, crates coming at you, your lamp
# the only light. Left/right to change lane, Space to start, Esc to stop.
#
# It plays in real time; facility time passes when a run ends (RUN_MINUTES:
# you lost track of time). Recreational software is against the Code of
# Conduct, so the first run each time it's opened is logged as a violation.
#
# Secrets (see docs/STORY.md):
#   - the high score table. Marrow's top score is the maintenance account's
#     password ("the top score. always the top score.")
#   - the NO ENTRY sign on the left shoulder at the start of every run. Hold
#     left against it until you slip through, and you're on the wrong road,
#     where Marrow left a message.
class_name NightRunApp
extends OSApp

const RUN_MINUTES := 10.0
const VIOLATION := 3.0
const LANES := 3
const START_SPEED := 240.0
const MAX_SPEED := 640.0
const ACCEL := 9.0
## Seconds the NO ENTRY sign is on screen at the start of a run...
const SIGN_TIME := 4.5
## ...and how long to push into it.
const WRONG_WAY_PUSH := 1.6
## The scores the machine came with. Marrow's is the password; nobody beats it.
const BUILT_IN := [["RM", 709142], ["RM", 402377], ["DO", 88410], ["RM", 71200], ["DO", 61955], ["JK", 1200], ["TV", 340]]
const MESSAGE := [
	"YOU WENT THE WRONG WAY.",
	"GOOD.",
	"",
	"THE OLD MAN'S WORD IS KEPT",
	"BY THE ONE WHO NEVER LEAVES.",
	"",
	"ASK IT ABOUT ITS LIGHT.",
	"ASK GENTLY.",
	"",
	"                        - R.M.",
]

var screen: Control
## "title", "run", "crash", "wrong_way"
var state := "title"
var lane := 1
var cart_x := 1.0         # smooth lane position
var speed := START_SPEED
var distance := 0.0
var score := 0
var run_time := 0.0
var crates: Array[Vector2] = []   # (lane, y)
var scores: Array = []            # the player's: [["SUP", n], ...]
var runs_this_session := 0
var push_left := 0.0
var message_time := 0.0
var rng := RandomNumberGenerator.new()
var _spawn := 0.0
var _scroll := 0.0
var _left_was := false
var _right_was := false


func _init() -> void:
	app_id = "nightrun"
	title = "NIGHT RUN"
	default_size = Vector2(560, 520)
	icon_text = "RUN"
	icon_color = Color("ff9a3c")


func build() -> void:
	rng.randomize()
	screen = Control.new()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.clip_contents = true
	screen.focus_mode = Control.FOCUS_NONE
	screen.draw.connect(_draw_screen)
	screen.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and state in ["title", "crash"]:
			start_run())
	add_child(screen)
	if sim():
		Story.learn(sim(), "secret:nightrun")
		Story.learn(sim(), "app:nightrun")


func save_state() -> Dictionary:
	return {"scores": scores}


func load_state(s: Dictionary) -> void:
	scores = s.get("scores", []).duplicate(true)


## Every score on the table, best first.
func table() -> Array:
	var all: Array = BUILT_IN.duplicate(true)
	all.append_array(scores)
	all.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return all.slice(0, 8)


func key_input(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_SPACE, KEY_ENTER:
			if state in ["title", "crash"]:
				start_run()
			return true
		KEY_ESCAPE:
			if state == "run":
				_end_run(false)
			return true
		KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D:
			return true
	return false


func start_run() -> void:
	state = "run"
	lane = 1
	cart_x = 1.0
	speed = START_SPEED
	distance = 0.0
	score = 0
	run_time = 0.0
	crates.clear()
	push_left = 0.0
	_spawn = 1.2


func _process(delta: float) -> void:
	if screen == null:
		return
	var focused: bool = desktop == null or (desktop.focused_window() != null and desktop.focused_window().app == self)
	var left := focused and (Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A))
	var right := focused and (Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D))
	step(delta, left, right)
	screen.queue_redraw()


## One frame of the game with these keys held (tests drive it directly).
func step(delta: float, left: bool, right: bool) -> void:
	match state:
		"run":
			_run_step(delta, left, right)
		"wrong_way":
			message_time += delta
			if message_time > MESSAGE.size() * 0.9 + 4.0:
				state = "title"
	_left_was = left
	_right_was = right


func _run_step(delta: float, left: bool, right: bool) -> void:
	run_time += delta
	# Lane changes on the press, not the hold.
	if left and not _left_was:
		lane = maxi(lane - 1, 0)
	if right and not _right_was:
		lane = mini(lane + 1, LANES - 1)
	cart_x = move_toward(cart_x, float(lane), delta * 9.0)
	# Pushing into the NO ENTRY shoulder while the sign is up.
	if run_time < SIGN_TIME and lane == 0 and left:
		push_left += delta
		if push_left >= WRONG_WAY_PUSH:
			_wrong_way()
			return
	elif not left:
		push_left = maxf(push_left - delta, 0.0)
	speed = minf(speed + ACCEL * delta, MAX_SPEED)
	distance += speed * delta
	_scroll = fmod(_scroll + speed * delta, 80.0)
	score = int(distance / 4.0)
	# Crates: none while the sign is up, then more as it gets faster.
	_spawn -= delta
	if _spawn <= 0.0 and run_time > SIGN_TIME:
		crates.append(Vector2(rng.randi() % LANES, -40.0))
		if rng.randf() < 0.25 + speed / MAX_SPEED * 0.3:
			crates.append(Vector2(rng.randi() % LANES, -140.0))
		_spawn = rng.randf_range(0.45, 1.1) * START_SPEED / speed * 1.6
	var h := screen.size.y if screen.size.y > 0.0 else 460.0
	var cart_y := h - 70.0
	for i in range(crates.size() - 1, -1, -1):
		crates[i].y += speed * delta
		if crates[i].y > h + 40.0:
			crates.remove_at(i)
		elif absf(crates[i].x - cart_x) < 0.55 and absf(crates[i].y - cart_y) < 34.0:
			_end_run(true)
			return


func _end_run(crashed: bool) -> void:
	state = "crash" if crashed else "title"
	if score > 0:
		scores.append(["SUP", score])
		scores.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
		scores = scores.slice(0, 8)
	_spend_time()


func _wrong_way() -> void:
	state = "wrong_way"
	message_time = 0.0
	crates.clear()
	if sim():
		Story.learn(sim(), "secret:wrong_way")
		Story.learn(sim(), "hint:lantern")
	_spend_time()


func _spend_time() -> void:
	runs_this_session += 1
	if sim():
		Supervisor.play(RUN_MINUTES, "Night Run", VIOLATION if runs_this_session == 1 else 0.0)


# --- Drawing ------------------------------------------------------------------------

const BG := Color("07090a")
const ROAD := Color("15191b")
const LAMP := Color("ffcf6a")
const CRATE := Color("8a5a2b")
const TEXT_C := Color("ff9a3c")


func _lane_x(l: float) -> float:
	var w := screen.size.x
	var road_w := minf(w * 0.6, 300.0)
	return (w - road_w) * 0.5 + road_w * (l + 0.5) / LANES


func _draw_screen() -> void:
	var s := screen.size
	screen.draw_rect(Rect2(Vector2.ZERO, s), BG)
	var font := Mono.font()
	match state:
		"wrong_way":
			_draw_wrong_way(font)
			return
		"title", "crash":
			_draw_road(false)
			_draw_title(font)
			return
	_draw_road(true)
	# The lamp: a cone of light up the road from the cart. Crates outside it are barely there.
	var cart := Vector2(_lane_x(cart_x), s.y - 70.0)
	var cone := PackedVector2Array([cart + Vector2(-10, -14), cart + Vector2(-90, -s.y * 0.55), cart + Vector2(90, -s.y * 0.55), cart + Vector2(10, -14)])
	screen.draw_colored_polygon(cone, Color(LAMP, 0.07))
	for c in crates:
		var p := Vector2(_lane_x(c.x), c.y)
		var lit := clampf(1.0 - (cart.y - p.y) / (s.y * 0.6), 0.08, 1.0) if p.y < cart.y else 1.0
		screen.draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(CRATE, lit))
		screen.draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(0, 0, 0, lit * 0.6), false, 2.0)
	screen.draw_rect(Rect2(cart - Vector2(16, 20), Vector2(32, 40)), Color("3a3f44"))
	screen.draw_circle(cart + Vector2(0, -16), 5.0, LAMP)
	screen.draw_string(font, Vector2(12, 24), "SCORE %06d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_C)
	if run_time < SIGN_TIME:
		var sign_y := 80.0 + run_time * 50.0
		var left_edge := _lane_x(-0.5) - 12.0
		screen.draw_rect(Rect2(Vector2(left_edge - 86, sign_y), Vector2(78, 34)), Color("b3261e"))
		screen.draw_string(font, Vector2(left_edge - 80, sign_y + 22), "NO ENTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		screen.draw_string(font, Vector2(left_edge - 64, sign_y + 52), "<---", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b3261e"))
		if push_left > 0.0:
			screen.draw_rect(Rect2(Vector2(left_edge - 4, cart.y - 30), Vector2(4, 60)), Color(1, 1, 1, push_left / WRONG_WAY_PUSH))


func _draw_road(moving: bool) -> void:
	var s := screen.size
	var x0 := _lane_x(-0.5)
	var x1 := _lane_x(LANES - 0.5)
	screen.draw_rect(Rect2(Vector2(x0, 0), Vector2(x1 - x0, s.y)), ROAD)
	screen.draw_line(Vector2(x0, 0), Vector2(x0, s.y), Color("3a3f44"), 3.0)
	screen.draw_line(Vector2(x1, 0), Vector2(x1, s.y), Color("3a3f44"), 3.0)
	var off := _scroll if moving else 0.0
	for l in range(1, LANES):
		var x := (_lane_x(l - 1) + _lane_x(l)) * 0.5
		var y := -80.0 + off
		while y < s.y:
			screen.draw_line(Vector2(x, y), Vector2(x, y + 36), Color("2a3033"), 2.0)
			y += 80.0


func _draw_title(font: Font) -> void:
	var s := screen.size
	var cx := s.x * 0.5
	screen.draw_rect(Rect2(Vector2(cx - 170, 40), Vector2(340, s.y - 80)), Color(0, 0, 0, 0.8))
	_centered(font, "NIGHT RUN", 70, 34, TEXT_C)
	_centered(font, "v0.9  by R.M.", 94, 12, Color(TEXT_C, 0.6))
	if state == "crash":
		_centered(font, "CRASHED  %06d" % score, 128, 16, Color("ff5a4a"))
	_centered(font, "HIGH SCORES", 162, 14, TEXT_C)
	var y := 188.0
	for row in table():
		_centered(font, "%-3s  %06d" % [row[0], int(row[1])], y, 16, Color("e8e2d0"))
		y += 22.0
	_centered(font, "SPACE TO RUN   ESC TO STOP", s.y - 60, 12, Color(TEXT_C, 0.7))
	_centered(font, "(each run: %d facility minutes)" % int(RUN_MINUTES), s.y - 44, 11, Color(TEXT_C, 0.45))


func _draw_wrong_way(font: Font) -> void:
	var s := screen.size
	# One lane, no crates, no lamp: just the dark and the words.
	screen.draw_rect(Rect2(Vector2(s.x * 0.5 - 30, 0), Vector2(60, s.y)), Color("0c0e0f"))
	var shown := int(message_time / 0.9)
	var y := 90.0
	for i in mini(shown, MESSAGE.size()):
		screen.draw_string(font, Vector2(s.x * 0.5 - 150, y), MESSAGE[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e8e2d0"))
		y += 24.0


func _centered(font: Font, text: String, y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	screen.draw_string(font, Vector2((screen.size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
