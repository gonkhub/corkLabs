# The audio buses, and the camera feed's mute and volume.
#
# Think of it as the mixer (the Audio tab at the bottom of the Godot editor
# shows the same thing; the layout is saved in res://default_bus_layout.tres):
#
#   Master
#   ├── Feed      everything you hear through a security camera. Mute button
#   │   │         in Cameras, volume in Settings.
#   │   ├── Voices   the robots' speech blips (RobotVoice)
#   │   └── World    positional sound in the facility (FacilitySound):
#   │                motors, machines, auditioned sounds
#   └── UI        the OS itself (corkHQ chime, future clicks and alerts)
#
# Put inserts (EQ, compressor, a "cheap CCTV mic" band-pass, reverb) on a bus
# in the editor's Audio tab and everything routed there gets them.
#
# If the layout file is missing a bus, ensure_buses() adds it at start-up
# with the routing above, so code can always rely on these names.
class_name FeedAudio
extends RefCounted

const FEED := &"Feed"
const VOICES := &"Voices"
const WORLD := &"World"
const UI := &"UI"
## bus -> the bus it sends to (parents before children).
const ROUTING := [[FEED, &"Master"], [VOICES, FEED], [WORLD, FEED], [UI, &"Master"]]


static func ensure_buses() -> void:
	for r in ROUTING:
		if AudioServer.get_bus_index(r[0]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, r[0])
			AudioServer.set_bus_send(i, r[1])


## Applies the saved feed mute and volume to the Feed bus.
static func apply() -> void:
	ensure_buses()
	var i := AudioServer.get_bus_index(FEED)
	AudioServer.set_bus_mute(i, bool(OSSettings.get_value("feed_muted")))
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(OSSettings.get_value("feed_volume")), 0.0001)))


static func is_muted() -> bool:
	return bool(OSSettings.get_value("feed_muted"))


static func set_muted(on: bool) -> void:
	OSSettings.set_value("feed_muted", on)
	apply()


static func set_volume(linear: float) -> void:
	OSSettings.set_value("feed_volume", clampf(linear, 0.0, 1.0))
	apply()
