# Applies take names chosen in the editor's "Name your new takes" window.
# The window writes a JSON list of decisions and runs this headless, so the
# renaming and baking use the same code as everything else.
#
#   Godot --headless --xr-mode off --path . --script res://tools/apply_take_names.gd -- --manifest <file.json>
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--manifest")
	if i < 0 or i + 1 >= args.size():
		print("usage: -- --manifest <file.json>")
		quit(2)
		return
	var text := FileAccess.get_file_as_string(args[i + 1])
	var entries = JSON.parse_string(text)
	if not entries is Array:
		print("FAIL  could not read manifest %s" % args[i + 1])
		quit(1)
		return
	for line in TakeNaming.apply(entries):
		print(line)
	quit()
