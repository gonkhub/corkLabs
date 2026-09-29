# VR is switched on for the whole project (the recorder needs it at startup),
# so every scene you run starts an OpenXR session with the headset. Flat
# monitor scenes call FlatScreen.disable_xr() first thing, which ends that
# session so the game renders normally to the window instead of waiting on
# the headset.
class_name FlatScreen
extends RefCounted


static func disable_xr(viewport: Viewport) -> void:
	viewport.use_xr = false
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr.uninitialize()
		print("FlatScreen: OpenXR session closed; running on the monitor.")
