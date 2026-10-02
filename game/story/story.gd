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


# --- Accounts and permissions -----------------------------------------------------

## Which account the terminal is logged in as: "supervisor", "dokafor" (Okafor's
## old account), or "maint" (the maintenance account, which opens everything).
static func user(sim: FacilitySim) -> String:
	if knows(sim, "root"):
		return "maint"
	if knows(sim, "as:dokafor"):
		return "dokafor"
	return "supervisor"


## Can the current account open this path? (Every folder above it must let it in.)
static func can_access(sim: FacilitySim, vpath: String) -> bool:
	var who := user(sim)
	if who == "maint":
		return true
	var e := entry(sim, vpath)
	while not e.is_empty():
		var acc := str(e.meta.get("access", ""))
		if not acc.is_empty() and not acc.split(" ", false).has(who):
			return false
		if str(e.parent).is_empty():
			return true
		e = fs().get_entry(str(e.parent))
	return true


## An entry by path: the file system's, or one of the supervisor's copies.
static func entry(sim: FacilitySim, vpath: String) -> Dictionary:
	if vpath.begins_with(VirtualFS.HOME + "/"):
		for c in copies(sim):
			if c.path == vpath:
				return c
	return fs().get_entry(vpath)


static func exists(sim: FacilitySim, vpath: String) -> bool:
	if vpath.begins_with(VirtualFS.HOME + "/"):
		for c in copies(sim):
			if c.path == vpath:
				return true
	return fs().exists(vpath, knowledge(sim), shift(sim))


static func list(sim: FacilitySim, vdir: String, show_hidden := false) -> Array[Dictionary]:
	var out := fs().children(vdir, knowledge(sim), shift(sim), show_hidden)
	if vdir == VirtualFS.HOME:
		for c in copies(sim):
			if show_hidden or not str(c.name).begins_with("."):
				out.append(c)
		out.sort_custom(func(a, b): return [not a.dir, a.name] < [not b.dir, b.name])
	return out


# --- Copies -------------------------------------------------------------------------
# "cp <file>" copies a file into the supervisor's home folder (Knowledge
# "copied:<source path>"). A copy keeps its text when the original is purged:
# the one way to keep Okafor's files.

## The supervisor's copies, as file entries in their home folder.
static func copies(sim: FacilitySim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var k := knowledge(sim)
	if k == null:
		return out
	for src in k.with_prefix("copied:"):
		var e := fs().get_entry(src)
		if e.is_empty():
			continue
		out.append({"path": VirtualFS.HOME + "/" + str(e.name), "name": e.name, "dir": false, "parent": VirtualFS.HOME,
			"meta": {"owner": "supervisor", "date": "today", "copy_of": src}, "body": e.body})
	return out


## Copies a file into the home folder. Returns {"ok", "text"}.
static func copy_file(sim: FacilitySim, src: String) -> Dictionary:
	var e := entry(sim, src)
	if e.is_empty() or not exists(sim, src):
		return {"ok": false, "text": "cp: %s: No such file" % src}
	if e.dir:
		return {"ok": false, "text": "cp: %s: Is a directory" % src}
	if not can_access(sim, src):
		return {"ok": false, "text": "cp: %s: Permission denied" % src}
	if e.meta.has("copy_of") or str(e.parent) == VirtualFS.HOME:
		return {"ok": false, "text": "cp: %s is already in your home folder" % e.name}
	if e.meta.has("password") or e.meta.has("exec"):
		return {"ok": false, "text": "cp: %s: can't be copied" % e.name}
	if exists(sim, VirtualFS.HOME + "/" + str(e.name)):
		return {"ok": false, "text": "cp: ~/%s already exists" % e.name}
	learn(sim, "copied:" + src)
	var r := restricted(e)
	var o := oversight(sim)
	if r > 0.0 and o:
		o.violate(sim, "copied %s" % src, r + 1.0)
	if src.begins_with("/home/dokafor/"):
		learn(sim, "secret:kept")
	return {"ok": true, "text": "Copied to ~/%s" % e.name}


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
	var e := entry(sim, vpath)
	if e.is_empty() or not exists(sim, vpath):
		return {"ok": false, "error": "%s: No such file or directory" % vpath}
	if e.dir:
		return {"ok": false, "error": "%s: Is a directory" % vpath}
	if not can_access(sim, vpath):
		return {"ok": false, "error": "%s: Permission denied" % vpath, "denied": true}
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
	var e := entry(sim, vpath)
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
