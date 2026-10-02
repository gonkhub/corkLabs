# Checks every conversation script (game/story/dialogue/*.txt) for the
# mistakes that are easy to make by hand: a choice or jump to a node that
# doesn't exist; a node nothing leads to; a node from which the conversation
# can never end; two ways to close the link offered at once; lines written
# after a node's choices (they never play); a speaker that isn't anyone;
# an effect nobody understands.
extends SceneTree

const DIR := "res://game/story/dialogue/"
const EFFECTS := ["learn", "forget", "stability", "perform", "accident", "directive", "suspicion", "standing", "hq", "fault",
	"say", "seize", "wear", "audit", "job", "end", "trust"]

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".txt"):
			_check_script(file.get_basename())
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _check_script(id: String) -> void:
	var d := Dialogue.parse(FileAccess.get_file_as_string(DIR + id + ".txt"))
	var problems := PackedStringArray()
	if not d.nodes.has("start"):
		problems.append("no start node")
	var speakers := ["you", "sys", "unit", id, "pell"]
	# Targets exist; lines after choices; speakers; effects; duplicate exits.
	for n in d.nodes:
		var seen_choice := false
		var exits := 0
		for s in d.nodes[n]:
			match s.kind:
				"goto", "choice":
					if s.target != "END" and not d.nodes.has(s.target):
						problems.append("%s: goes to a missing node '%s'" % [n, s.target])
					if s.kind == "choice":
						seen_choice = true
						if s.target == "END" and str(s.cond).is_empty():
							exits += 1
				"line":
					if seen_choice:
						problems.append("%s: a line after its choices never plays (\"%s\")" % [n, str(s.text).left(40)])
					if not s.speaker in speakers:
						problems.append("%s: unknown speaker '%s'" % [n, s.speaker])
				"effect":
					if not s.action in EFFECTS:
						problems.append("%s: unknown effect '%s'" % [n, s.action])
		if exits > 1:
			problems.append("%s: %d ways to close the link at once" % [n, exits])
	# Reachable from start; the end reachable from everywhere.
	var edges := {}
	for n in d.nodes:
		edges[n] = []
		var falls_off := true
		for s in d.nodes[n]:
			if s.kind in ["goto", "choice"]:
				edges[n].append(s.target)
				if s.kind == "goto" and str(s.cond).is_empty():
					falls_off = false
			if s.kind == "choice":
				falls_off = false
		if falls_off:
			edges[n].append("END")   # running off a node with no choices ends it
	var reach := _reachable(edges, "start")
	for n in d.nodes:
		if not reach.has(n):
			problems.append("%s: nothing leads here" % n)
		elif not _reachable(edges, n).has("END"):
			problems.append("%s: the conversation can never end from here" % n)
	_check(problems.is_empty(), "%s.txt is sound%s" % [id, "" if problems.is_empty() else ":\n      " + "\n      ".join(problems)])


func _reachable(edges: Dictionary, from: String) -> Dictionary:
	var seen := {from: true}
	var todo: Array = [from]
	while not todo.is_empty():
		var n: String = todo.pop_back()
		for t in edges.get(n, []):
			if not seen.has(t):
				seen[t] = true
				todo.append(t)
	return seen


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS  " + what)
	else:
		failures += 1
		print("FAIL  " + what)
