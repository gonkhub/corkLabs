# Story helpers: one place for what happens when the supervisor reads a
# file, decrypts one, or asks what exists, whichever app they use (Terminal
# or Files). No facility time is spent here: callers go through Supervisor,
# which spends what these return ("minutes").
class_name Story
extends RefCounted

## The maintenance account's password: Marrow's top score in Night Run.
const MAINT_PASSWORD := "709142"
const PODS_PATH := "res://game/story/pods.txt"

static var _pods: Array[Dictionary] = []


## The pods as the maintenance console sees them: [{"pod", "occupant", "name", "since", "dream"}]
static func pods() -> Array[Dictionary]:
	if _pods.is_empty():
		for row in DataTable.read(PODS_PATH, PackedStringArray(["pod", "occupant", "name", "since", "dream"])):
			row.dream = str(row.dream).replace("\\n", "\n")
			_pods.append(row)
	return _pods


static func knowledge(sim: FacilitySim) -> Knowledge:
	return sim.get_system("knowledge") as Knowledge if sim else null


static func oversight(sim: FacilitySim) -> Oversight:
	return sim.get_system("oversight") as Oversight if sim else null


static func campaign(sim: FacilitySim) -> Campaign:
	return sim.get_system("campaign") as Campaign if sim else null


## The shift that's running (or about to), 1 if there's no campaign.
static func shift(sim: FacilitySim) -> int:
	var c := campaign(sim)
	return c.shift if c else 1


static func fs() -> VirtualFS:
	return VirtualFS.shared()


static func knows(sim: FacilitySim, key: String) -> bool:
	var k := knowledge(sim)
	return k != null and k.has(key)


static func learn(sim: FacilitySim, key: String) -> bool:
	var k := knowledge(sim)
	return k != null and k.learn(sim, key)


static func exists(sim: FacilitySim, vpath: String) -> bool:
	return fs().exists(vpath, knowledge(sim), shift(sim))


static func list(sim: FacilitySim, vdir: String, show_hidden := false) -> Array[Dictionary]:
	return fs().children(vdir, knowledge(sim), shift(sim), show_hidden)


static func is_encrypted(sim: FacilitySim, e: Dictionary) -> bool:
	return e.meta.has("password") and not knows(sim, "decrypted:" + str(e.path))


## How much reading this is a violation (its own, or its folder's).
static func restricted(e: Dictionary) -> float:
	if e.meta.has("restricted"):
		return float(e.meta.restricted)
	var parent := fs().get_entry(str(e.parent))
	while not parent.is_empty():
		if parent.meta.has("restricted"):
			return float(parent.meta.restricted)
		parent = fs().get_entry(str(parent.parent))
	return 0.0


## Reads a file. Returns {"ok", "text", "error", "minutes", "first", "learned": [keys], "entry"}.
## First read: its "learn" keys (and its folder's) are learned, a restricted
## file is logged as a violation, and it costs its reading time. Re-reading
## is free.
static func read_file(sim: FacilitySim, vpath: String) -> Dictionary:
	var e := fs().get_entry(vpath)
	if e.is_empty() or not exists(sim, vpath):
		return {"ok": false, "error": "%s: No such file or directory" % vpath}
	if e.dir:
		return {"ok": false, "error": "%s: Is a directory" % vpath}
	if is_encrypted(sim, e):
		learn(sim, "cmd:decrypt")
		return {"ok": false, "error": "%s: encrypted. (decrypt %s <password>)" % [vpath, e.name], "encrypted": true, "entry": e,
			"text": _scramble(str(e.body))}
	if e.meta.has("exec"):
		learn(sim, "cmd:run")
	var first := not knows(sim, "read:" + vpath)
	var learned: Array[String] = []
	var minutes := 0.0
	if first:
		learn(sim, "read:" + vpath)
		minutes = VirtualFS.read_minutes(e)
		var keys := str(e.meta.get("learn", "")).split(" ", false)
		var parent := fs().get_entry(str(e.parent))
		while not parent.is_empty():
			keys.append_array(str(parent.meta.get("learn", "")).split(" ", false))
			parent = fs().get_entry(str(parent.parent))
		for key in keys:
			if learn(sim, key):
				learned.append(key)
		var r := restricted(e)
		var o := oversight(sim)
		if r > 0.0 and o:
			o.violate(sim, "read %s" % vpath, r)
	return {"ok": true, "text": str(e.body), "minutes": minutes, "first": first, "learned": learned, "entry": e}


## Tries a password. Returns {"ok", "text"}. A right password decrypts it for good.
static func decrypt(sim: FacilitySim, vpath: String, password: String) -> Dictionary:
	var e := fs().get_entry(vpath)
	if e.is_empty() or not exists(sim, vpath) or e.dir:
		return {"ok": false, "text": "decrypt: %s: No such file" % vpath}
	if not e.meta.has("password"):
		return {"ok": false, "text": "decrypt: %s is not encrypted" % vpath}
	if knows(sim, "decrypted:" + vpath):
		return {"ok": true, "text": "%s is already decrypted." % e.name}
	if password.strip_edges().to_lower() != str(e.meta.password).to_lower():
		return {"ok": false, "text": "decrypt: wrong password"}
	learn(sim, "decrypted:" + vpath)
	return {"ok": true, "text": "%s decrypted. (cat it)" % e.name}


# What an encrypted file looks like: noise the same shape as the text.
static func _scramble(text: String) -> String:
	var noise := "#%&@$*!?/|01ABCDEFXZ"
	var out := ""
	var h := 7
	for i in mini(text.length(), 360):
		var ch := text[i]
		if ch == "\n" or ch == " ":
			out += ch
		else:
			h = (h * 31 + ch.unicode_at(0)) % 9973
			out += noise[h % noise.length()]
	return out
