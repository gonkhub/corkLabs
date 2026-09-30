# Software packages (sim_id "software"): what's on the Cork package server,
# what the supervisor has requested, what corporate approved, what's
# installed. Packages unlock new possibilities; most are placeholders for
# now (packages.txt says which are wired).
#
# The supervisor does it all from the Terminal, and has to learn how (IT
# Services' welcome message gives the server address; the server explains
# the rest):
#   connect cork://pkg.corklabs.int     open a session with the package server
#   corkpkg list / info <id>             what's there, and what it needs
#   corkpkg request <id>                 ask corporate; approval arrives in corkHQ
#                                        with an install code (or a denial)
#   corkpkg install <id> <code>          download + install (takes facility time)
#   corkpkg installed
#
# CLEARANCE (1-3): corporate only approves packages up to the supervisor's
# clearance. Good shift reviews (A/B) raise it, an F lowers it.
class_name SoftwareLibrary
extends RefCounted

const PACKAGES_PATH := "res://game/corporate/packages.txt"
## Facility seconds before corporate answers a request.
const REVIEW_TIME := Vector2(300.0, 1800.0)
const MAX_CLEARANCE := 3

var sim_id := "software"
## [{"id", "name", "version", "size", "clearance", "minutes", "wired", "description"}]
var packages: Array[Dictionary] = []
var clearance := 1
## id -> {"status": "requested"/"approved"/"denied", "code": String}
var requests := {}
var installed_ids: Array[String] = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	for row in DataTable.read(PACKAGES_PATH, PackedStringArray(["id", "name", "version", "size", "clearance", "minutes", "wired", "description"])):
		row.size = int(row.size)
		row.clearance = int(row.clearance)
		row.minutes = float(row.minutes)
		row.wired = row.wired.to_lower() == "yes"
		packages.append(row)


func package(id: String) -> Dictionary:
	for p in packages:
		if p.id == id:
			return p
	return {}


func installed(id: String) -> bool:
	return installed_ids.has(id)


## Ask corporate for a package. Returns a line for the terminal.
func request(sim: FacilitySim, id: String) -> String:
	var p := package(id)
	if p.is_empty():
		return "corkpkg: no package '%s'" % id
	if installed(id):
		return "corkpkg: %s is already installed" % id
	var r: Dictionary = requests.get(id, {})
	if r.get("status", "") in ["requested", "approved"]:
		return "corkpkg: %s is already %s" % [id, r.status]
	requests[id] = {"status": "requested", "code": ""}
	sim.schedule_in(rng.randf_range(REVIEW_TIME.x, REVIEW_TIME.y), "software_review", {"package": id})
	var hq := _hq(sim)
	if hq:
		hq.post(sim, "IT Services", "software", "Request for %s %s logged. Awaiting review." % [p.name, p.version])
	return "Request sent to IT Services. Watch corkHQ for the decision."


## Install with the code corkHQ gave. Returns {"ok", "text", "minutes"}.
## The caller spends the install time.
func install(sim: FacilitySim, id: String, code: String) -> Dictionary:
	var p := package(id)
	if p.is_empty():
		return {"ok": false, "text": "corkpkg: no package '%s'" % id}
	if installed(id):
		return {"ok": false, "text": "corkpkg: %s is already installed" % id}
	var r: Dictionary = requests.get(id, {})
	if r.get("status", "") != "approved":
		return {"ok": false, "text": "corkpkg: %s is not approved for this facility (corkpkg request %s)" % [id, id]}
	if code.strip_edges().to_upper() != str(r.code):
		return {"ok": false, "text": "corkpkg: invalid install code for %s" % id}
	installed_ids.append(id)
	r.status = "installed"
	sim.note("software", "Installed %s %s" % [p.name, p.version])
	var hq := _hq(sim)
	if hq:
		hq.post(sim, "IT Services", "software", "%s %s installed. Usage is monitored." % [p.name, p.version])
	return {"ok": true, "text": "%s %s installed." % [p.name, p.version], "minutes": p.minutes}


## Shift review: clearance follows the grade.
func review(sim: FacilitySim, grade: String) -> void:
	var before := clearance
	if grade in ["A", "B"]:
		clearance = mini(clearance + 1, MAX_CLEARANCE)
	elif grade == "F":
		clearance = maxi(clearance - 1, 1)
	var hq := _hq(sim)
	if hq and clearance != before:
		hq.say(sim, "clearance_up" if clearance > before else "clearance_down", "software", {"clearance": clearance})


func sim_start(sim: FacilitySim) -> void:
	rng.seed = sim.rng.randi()


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	if event_name != "software_review":
		return
	var id := str(data.package)
	var p := package(id)
	var r: Dictionary = requests.get(id, {})
	if p.is_empty() or r.get("status", "") != "requested":
		return
	var hq := _hq(sim)
	if int(p.clearance) <= clearance:
		r.status = "approved"
		r.code = _code()
		if hq:
			hq.post(sim, "IT Services", "software", "APPROVED: %s %s. Install code: %s  (corkpkg install %s %s)" % [
				p.name, p.version, r.code, id, r.code], r.code)
	else:
		r.status = "denied"
		if hq:
			hq.post(sim, "IT Services", "software", "DENIED: %s requires clearance level %d. Yours is %d." % [p.name, p.clearance, clearance])


func _code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var out := ""
	for i in 6:
		if i == 3:
			out += "-"
		out += chars[rng.randi() % chars.length()]
	return out


func _hq(sim: FacilitySim) -> CorkHQ:
	return sim.get_system("hq") as CorkHQ


func sim_save() -> Dictionary:
	return {"clearance": clearance, "requests": requests.duplicate(true), "installed": installed_ids.duplicate(),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func sim_load(d: Dictionary) -> void:
	clearance = int(d.get("clearance", 1))
	requests = d.get("requests", {}).duplicate(true)
	installed_ids.clear()
	for id in d.get("installed", []):
		installed_ids.append(str(id))
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	return PackedStringArray(["SOFTWARE  clearance %d   installed: %s" % [clearance, ", ".join(installed_ids) if not installed_ids.is_empty() else "none"]])
