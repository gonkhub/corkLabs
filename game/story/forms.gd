# Paperwork (sim_id "forms"): corporate's forms, filed from the Forms app.
# Paperwork is a pacing tool: the things that matter most (an essential
# replacement part, later perhaps an authorisation) sit behind a form that
# costs a big chunk of the shift to fill in, and that needs facts the
# supervisor has to go and find (a serial number in a file, a fault code from
# a diagnostic). Facts like that are what the Notes app is for: written down
# once, they're quick to fill in on the next run.
#
# Forms are data (game/story/forms.txt). Filing one puts it under review
# (REVIEW facility seconds); then it's approved (its action runs, Knowledge
# "filed:<id>") or returned with the first answer that didn't match.
class_name Forms
extends RefCounted

const PATH := "res://game/story/forms.txt"
## How long corporate takes to review a filed form (facility seconds).
const REVIEW := Vector2(1800.0, 3600.0)

var sim_id := "forms"
## form id -> {"status": "review" / "returned" / "approved", "t", "why"}
var filed := {}
var rng := RandomNumberGenerator.new()
static var _defs: Array[Dictionary] = []


static func defs() -> Array[Dictionary]:
	if _defs.is_empty():
		for row in DataTable.read(PATH, PackedStringArray(["id", "title", "minutes", "fields", "action", "description"])):
			var fields: Array[Dictionary] = []
			for pair in str(row.fields).split(";", false):
				var kv := pair.split("=")
				if kv.size() == 2:
					fields.append({"label": kv[0].strip_edges(), "answer": kv[1].strip_edges()})
			row.fields = fields
			row.minutes = float(row.minutes)
			_defs.append(row)
	return _defs


static func def(id: String) -> Dictionary:
	for d in defs():
		if str(d.id) == id:
			return d
	return {}


## The forms this supervisor has been issued.
static func available(sim: FacilitySim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in defs():
		if Story.knows(sim, "form:" + str(d.id)):
			out.append(d)
	return out


## What corporate thinks of a form right now: "" (not filed), "review", "returned", "approved".
func status(id: String) -> String:
	return str(filed.get(id, {}).get("status", ""))


## Files a form with these answers (label -> text). Returns "" or why not.
func submit(sim: FacilitySim, id: String, answers: Dictionary) -> String:
	var d := def(id)
	if d.is_empty() or not Story.knows(sim, "form:" + id):
		return "No such form."
	if status(id) in ["review", "approved"]:
		return "It's already %s." % ("under review" if status(id) == "review" else "approved")
	var wrong := ""
	for f in d.fields:
		if _norm(str(answers.get(f.label, ""))) != _norm(str(f.answer)):
			wrong = str(f.label)
			break
	filed[id] = {"status": "review", "t": sim.time(), "why": wrong}
	# Reviewed once it's filled in (the filing takes its minutes), and then some.
	sim.schedule_in(float(d.minutes) * 60.0 + rng.randf_range(REVIEW.x, REVIEW.y), "form_review", {"form": id})
	sim.note("forms", "%s filed: under review" % d.title)
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.post(sim, "Procurement", "notice", "%s received. Under review." % d.title)
	return ""


static func _norm(t: String) -> String:
	return t.strip_edges().to_upper().replace(" ", "").replace("-", "").replace(".", "").replace("_", "")


func sim_start(sim: FacilitySim) -> void:
	rng.seed = sim.rng.randi()


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	if event_name != "form_review":
		return
	var id := str(data.get("form", ""))
	var f: Dictionary = filed.get(id, {})
	var d := def(id)
	if f.is_empty() or f.status != "review" or d.is_empty():
		return
	var hq := sim.get_system("hq") as CorkHQ
	if not str(f.why).is_empty():
		f.status = "returned"
		sim.note("forms", "%s returned: %s" % [d.title, f.why])
		if hq:
			hq.post(sim, "Procurement", "warning", "%s RETURNED: the %s does not match our records. Correct it and file it again." % [d.title, str(f.why).to_lower()])
		return
	f.status = "approved"
	var k := sim.get_system("knowledge") as Knowledge
	if k:
		k.learn(sim, "filed:" + id)
	sim.note("forms", "%s approved" % d.title)
	if hq:
		hq.post(sim, "Procurement", "order", "%s APPROVED." % d.title)
	match str(d.action):
		"core":
			var req := sim.get_system("requisitions") as Requisitions
			if req:
				req.ship_core(sim)


func sim_save() -> Dictionary:
	return {"filed": filed.duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func sim_load(d: Dictionary) -> void:
	filed = d.get("filed", {}).duplicate(true)
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["FORMS"])
	for id in filed:
		lines.append("  %s: %s %s" % [id, filed[id].status, filed[id].why])
	return lines
