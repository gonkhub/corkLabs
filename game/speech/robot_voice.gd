# A robot's voice: short blips, one per letter as its words appear on
# camera (like old game dialogue). Built from its traits: pitch, variation,
# wave shape. The blips are generated once (a handful of pitches) and played
# from a small pool of players, so talking costs next to nothing.
#
# Placeholder for real sound design: give it recorded samples with
# `use_samples([...])` and it'll play those instead, same way.
class_name RobotVoice
extends Node

const MIX_RATE := 22050
const BLIP_SECONDS := 0.055
const VARIANTS := 8
const POOL := 4

var traits: RobotTraits
var volume_db := -8.0:
	set(v):
		volume_db = v
		for p in _players:
			p.volume_db = v

var _blips: Array[AudioStream] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func setup(robot_traits: RobotTraits) -> void:
	traits = robot_traits
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = volume_db
		p.bus = FeedAudio.VOICES   # under the camera Feed bus: the feed's mute silences it
		add_child(p)
		_players.append(p)
	for i in VARIANTS:
		var spread := (float(i) / (VARIANTS - 1)) * 2.0 - 1.0   # -1..1
		_blips.append(_make_blip(traits.voice_pitch * (1.0 + traits.voice_variation * 0.5 * spread), traits.voice_wave))


## Swap the generated blips for recorded ones (any AudioStreams).
func use_samples(samples: Array[AudioStream]) -> void:
	if not samples.is_empty():
		_blips = samples.duplicate()


## One blip for this letter (the same letter always gets the same pitch).
func blip(ch: String) -> void:
	if _blips.is_empty() or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _blips[ch.unicode_at(0) % _blips.size()]
	p.play()


static func _make_blip(freq: float, wave: String) -> AudioStreamWAV:
	var n := int(MIX_RATE * BLIP_SECONDS)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var noise := RandomNumberGenerator.new()
	noise.seed = int(freq)
	for i in n:
		phase = fmod(phase + freq / MIX_RATE, 1.0)
		var v := 0.0
		match wave:
			"sine": v = sin(phase * TAU)
			"saw": v = phase * 2.0 - 1.0
			"noise": v = noise.randf_range(-1.0, 1.0)
			_: v = 1.0 if phase < 0.5 else -1.0
		# Quick attack, gentle decay: a blip, not a click.
		var t := float(i) / n
		var env := minf(t * 20.0, 1.0) * pow(1.0 - t, 1.5)
		data.encode_s16(i * 2, int(clampf(v * env * 0.45, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
