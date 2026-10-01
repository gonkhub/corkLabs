# What the supervisor has found out (sim_id "knowledge"): terminal commands
# they've learned, files they've read, secrets, and story flags. One flat set
# of keys, saved with the facility, so a retried shift forgets what was
# learned after its checkpoint.
#
# Keys by prefix (a convention, nothing enforces it):
#   cmd:<name>      a terminal command the supervisor knows (listed in "help")
#   app:<id>        an OS app that has appeared on the desktop
#   read:<path>     a file they've read (re-reading is free)
#   decrypted:<path> an encrypted file they've unlocked
#   secret:<id>     a secret (see secrets.txt; also counted across every run
#                   in the SupervisorArchive)
#   anything else   a story flag ("met:tinker", "purged:dokafor"...)
#
# Plus a few numbers (`values`): "trust:tinker" (conversations that counted),
# which conditions compare: "trust:tinker>=3".
#
# The PLAYER keeps what they know between runs: a hidden command typed on a
# brand-new save still works (and is learned then). Only the list in "help"
# and the desktop icons reset.
class_name Knowledge
extends RefCounted

## What every new supervisor starts knowing.
const START := ["cmd:help", "cmd:status", "cmd:ls", "cmd:cd", "cmd:cat", "cmd:pwd", "cmd:clear"]
const SECRETS_PATH := "res://game/story/secrets.txt"

var sim_id := "knowledge"
## key -> facility time it was learned
var flags := {}
## Numbers: "trust:<unit>" ...
var values := {}
## Learned keys, in order (the Terminal and toasts watch `learned_count`).
var recent: Array[String] = []
var learned_count := 0

static var _secrets: Array[Dictionary] = []


func has(key: String) -> bool:
	return flags.has(key)


## Learns `key`. Returns true if it was new. Commands and secrets are journaled.
func learn(sim: FacilitySim, key: String) -> bool:
	if key.is_empty() or flags.has(key):
		return false
	flags[key] = sim.time() if sim else 0.0
	learned_count += 1
	recent.append(key)
	if recent.size() > 20:
		recent.pop_front()
	if sim and (key.begins_with("cmd:") or key.begins_with("secret:") or key.begins_with("app:")):
		sim.note("story", "Learned %s" % describe(key))
	if key.begins_with("secret:"):
		SupervisorArchive.found_secret(key.trim_prefix("secret:"))
	return true


func forget(key: String) -> void:
	flags.erase(key)


func value(key: String) -> float:
	return float(values.get(key, 0.0))


func add_value(key: String, amount := 1.0) -> float:
	values[key] = value(key) + amount
	return float(values[key])


## Keys with this prefix, without it, sorted: with_prefix("cmd:") -> ["cat", "cd"...]
func with_prefix(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for k in flags:
		if str(k).begins_with(prefix):
			out.append(str(k).trim_prefix(prefix))
	out.sort()
	return out


## Checks a condition string: "flag", "!flag", or several joined by "&".
## Empty is always true.
func check(condition: String) -> bool:
	for part in condition.split("&", false):
		var c := part.strip_edges()
		if c.is_empty():
			continue
		if c.begins_with("!"):
			if has(c.substr(1)):
				return false
		elif not has(c):
			return false
	return true


## "the command 'talk'", "a secret: The maintenance account"...
static func describe(key: String) -> String:
	if key.begins_with("cmd:"):
		return "the command '%s'" % key.trim_prefix("cmd:")
	if key.begins_with("app:"):
		return "the app '%s'" % key.trim_prefix("app:")
	if key.begins_with("secret:"):
		return "a secret: %s" % secret_title(key.trim_prefix("secret:"))
	return key


# --- Secrets catalogue ------------------------------------------------------------

## [{"id", "title", "hint"}] from secrets.txt.
static func secrets() -> Array[Dictionary]:
	if _secrets.is_empty():
		_secrets = DataTable.read(SECRETS_PATH, PackedStringArray(["id", "title", "hint"]))
	return _secrets


static func secret_title(id: String) -> String:
	for s in secrets():
		if s.id == id:
			return s.title
	return id


# --- System ---------------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	for k in START:
		flags[k] = sim.time()


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass


func sim_save() -> Dictionary:
	return {"flags": flags.duplicate(), "learned": learned_count, "values": values.duplicate()}


func sim_load(d: Dictionary) -> void:
	flags = {}
	var f: Dictionary = d.get("flags", {})
	for k in f:
		flags[str(k)] = float(f[k])
	learned_count = int(d.get("learned", flags.size()))
	values = {}
	var v: Dictionary = d.get("values", {})
	for k in v:
		values[str(k)] = float(v[k])


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	return PackedStringArray(["KNOWLEDGE  %d keys   commands: %s   secrets: %s" % [flags.size(),
		" ".join(with_prefix("cmd:")), " ".join(with_prefix("secret:"))]])
