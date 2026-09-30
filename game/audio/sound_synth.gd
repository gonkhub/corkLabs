# Placeholder sounds, generated in code so there's something to hear before
# real sound design exists. Every one is a plain AudioStreamWAV, so a real
# recording can replace it anywhere without other changes.
#
#   tone    440 Hz sine, looped: the cleanest thing for judging attenuation
#   noise   soft filtered noise, looped: judging muffling through walls
#   hum     motor hum (a low buzz with a wobble), looped: robots moving
#   click   a short relay click, one-shot
class_name SoundSynth
extends RefCounted

const MIX_RATE := 22050
const NAMES := ["tone", "noise", "hum", "click"]

static var _cache := {}


## A built-in placeholder by name (null if there's no such one).
static func builtin(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var s: AudioStreamWAV
	match sound_name:
		"tone": s = _loop(_render(1.0, func(t: float, _i: int): return sin(t * 440.0 * TAU) * 0.5))
		"noise": s = _loop(_noise(2.0))
		"hum": s = _loop(_render(1.0, func(t: float, _i: int):
			# 60 Hz buzz with a couple of harmonics, gently wobbling (whole cycles, so it loops cleanly).
			var wob := 1.0 + 0.15 * sin(t * 4.0 * TAU)
			return (sin(t * 60.0 * TAU) * 0.5 + sin(t * 120.0 * TAU) * 0.3 + sin(t * 180.0 * TAU) * 0.15) * 0.5 * wob))
		"click": s = _render(0.04, func(t: float, i: int):
			var env := exp(-t * 180.0)
			return (sin(t * 2400.0 * TAU) * 0.6 + (fmod(i * 0.618, 1.0) * 2.0 - 1.0) * 0.4) * env)
		_: return null
	_cache[sound_name] = s
	return s


# Samples of f(t seconds, sample index) -> -1..1, as 16-bit mono.
static func _render(seconds: float, f: Callable) -> AudioStreamWAV:
	var n := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = f.call(float(i) / MIX_RATE, i)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _noise(seconds: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var smooth := 0.0
	var vals := PackedFloat32Array()
	var n := int(MIX_RATE * seconds)
	var fade := int(MIX_RATE * 0.05)
	vals.resize(n + fade)
	for i in n + fade:
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.25)   # one-pole low-pass: softer than white noise
		vals[i] = smooth * 0.9
	# Crossfade the extra tail into the start, so the jump from the end back to the start is seamless.
	for i in fade:
		vals[i] = lerpf(vals[n + i], vals[i], float(i) / fade)
	return _render(seconds, func(_t: float, i: int): return vals[i])


static func _loop(wav: AudioStreamWAV) -> AudioStreamWAV:
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = wav.data.size() / 2
	return wav
