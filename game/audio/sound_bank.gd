# Sounds by name, for auditioning (Terminal: `sound`) and for code that
# wants "the door sound" without knowing where it lives: files dropped in
# game/sounds/ first, then SoundSynth's built-in placeholders. So a recorded
# "hum.wav" in game/sounds/ replaces the generated hum wherever it's asked for
# by name.
class_name SoundBank
extends RefCounted

## Drop .wav / .ogg / .mp3 files here.
const SOUNDS_DIR := "res://game/sounds/"
const EXTENSIONS := ["wav", "ogg", "mp3"]


## Sounds to audition: files in SOUNDS_DIR (by name, no extension) and
## the built-in placeholders.
static func library() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(SOUNDS_DIR):
		f = f.trim_suffix(".import").trim_suffix(".remap")   # exported builds list the import files
		if f.get_extension().to_lower() in EXTENSIONS and not out.has(f.get_basename()):
			out.append(f.get_basename())
	for n in SoundSynth.NAMES:
		if not out.has(n):
			out.append(n)
	return out


## A sound by name: a file in SOUNDS_DIR first, else a built-in placeholder.
static func find_stream(sound_name: String) -> AudioStream:
	for ext in EXTENSIONS:
		var path: String = SOUNDS_DIR + sound_name + "." + ext
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return SoundSynth.builtin(sound_name)
