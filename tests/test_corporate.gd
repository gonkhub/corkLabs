# Checks the corporate systems: corkHQ (welcome, shift reviews and grades,
# nagging), the budget and requisitions (approval, denial, delivery),
# software packages (clearance, request -> approval code -> install, the
# packages that are wired), and the corkHQ panel on the desktop (pinned,
# unclosable, alerts on new messages).
extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_data()
	_test_hq_reviews()
	_test_requisitions()
	_test_software()
	await _test_panel()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _facility(seed_value := 3) -> FacilitySim:
	var sim := FacilitySim.new()
	var systems := FacilitySetup.systems()
	for s in systems:
		sim.add_system(s)
	sim.new_game(seed_value)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(sim)
	return sim


func _test_data() -> void:
	var req := Requisitions.new()
	var cats := req.categories()
	_check(cats.has("Resources") and cats.has("Parts") and cats.has("Robots"), "the catalogue has resources, parts and robots (%s)" % ", ".join(cats))
	_check(req.catalog.all(func(c): return int(c.price) > 0), "every item has a price")
	var sw := SoftwareLibrary.new()
	_check(sw.packages.size() >= 8, "a set of software packages (%d)" % sw.packages.size())
	var rows := DataTable.parse("# c\na | b | the rest | with | pipes\n\nx | y", PackedStringArray(["one", "two", "rest"]))
	_check(rows.size() == 2 and rows[0].rest == "the rest | with | pipes" and rows[1].rest == "", "data tables read pipes, comments, short rows")


func _test_hq_reviews() -> void:
	var sim := _facility()
	var hq: CorkHQ = sim.get_system("hq")
	var req: Requisitions = sim.get_system("requisitions")
	_check(hq.messages.size() >= 3 and hq.messages.any(func(m): return str(m.text).contains(CorkHQ.SERVER)),
		"corkHQ welcomes the supervisor, and IT gives the package server's address")
	_check(CorkHQ.grade_for(0.95) == "A" and CorkHQ.grade_for(0.86) == "B" and CorkHQ.grade_for(0.5) == "F", "grades follow throughput")
	var funds0 := req.funds
	sim.advance(9 * 3600.0)   # to 14:55: the Day shift ended at 14:00
	var reviews := hq.messages.filter(func(m): return m.kind == "review")
	_check(reviews.size() == 1 and hq.grade != "", "every shift ends with a graded review (%s)" % (reviews[0].text if not reviews.is_empty() else "-"))
	_check(req.funds == funds0 + int(Requisitions.ALLOCATION[hq.grade]), "the grade sets the budget allocation (+%d cr)" % (req.funds - funds0))
	_check(hq.messages.any(func(m): return m.kind == "directive" and str(m.text).contains("shift has begun")), "each shift starts with a directive")


func _test_requisitions() -> void:
	var sim := _facility(5)
	var req: Requisitions = sim.get_system("requisitions")
	var hq: CorkHQ = sim.get_system("hq")
	var plant: FacilityPlant = sim.get_system("plant")
	var funds0 := req.funds
	var too_much := req.place(sim, "robot_hauler")
	_check(not too_much.ok and req.funds == funds0, "you can't order beyond your budget (%s)" % too_much.text)
	plant.coolant = 0.3
	var r := req.place(sim, "coolant_canister", 1)
	_check(r.ok and req.funds == funds0 - 120 and r.order.status == "in transit", "an order is paid for and shipped")
	_check(hq.messages.back().kind == "order" and str(hq.messages.back().text).contains("shipped"), "corkHQ confirms it")
	sim.advance(3700.0)
	_check(r.order.status == "delivered" and plant.coolant > 0.65, "it's delivered, and coolant tops up the reservoir (%d%%)" % roundi(plant.coolant * 100))
	var parts := req.place(sim, "fuse_pack", 2)
	sim.advance(2.1 * 3600.0)
	_check(int(req.inventory.get("fuse_pack", 0)) == 2, "parts go into stock")
	# Needs approval: approved with a decent rating, denied (and refunded) with a poor one.
	req.funds = 10000
	hq.grade = "B"
	var ok := req.place(sim, "gate_actuator")
	_check(ok.order.status == "pending", "big items wait for corporate approval")
	sim.advance(3700.0)
	_check(ok.order.status in ["in transit", "delivered"], "a B rating gets it approved (%s)" % ok.order.status)
	hq.grade = "F"
	var funds_before := req.funds
	var no := req.place(sim, "robot_tinker")
	sim.advance(3700.0)
	_check(no.order.status == "denied" and req.funds == funds_before, "an F rating gets it denied, and refunded")
	_check(hq.messages.any(func(m): return str(m.text).contains("DENIED")), "corkHQ says so")
	_check(parts.ok, "sanity")


func _test_software() -> void:
	var sim := _facility(6)
	var sw: SoftwareLibrary = sim.get_system("software")
	var hq: CorkHQ = sim.get_system("hq")
	_check(sw.install(sim, "remote-reboot", "XXX-XXX").ok == false, "you can't install without approval")
	sw.request(sim, "remote-reboot")
	sim.advance(1900.0)
	var r: Dictionary = sw.requests["remote-reboot"]
	var approval := hq.messages.filter(func(m): return m.kind == "software" and str(m.code) != "")
	_check(r.status == "approved" and approval.size() == 1 and approval[0].code == r.code, "corporate approves it, with an install code (%s)" % r.code)
	_check(not sw.install(sim, "remote-reboot", "WRONG-1").ok, "a wrong code is refused")
	_check(sw.install(sim, "remote-reboot", r.code).ok and sw.installed("remote-reboot"), "the right code installs it")
	sw.request(sim, "overclock")
	sim.advance(1900.0)
	_check(sw.requests["overclock"].status == "denied", "packages above your clearance are denied")
	sw.review(sim, "A")
	_check(sw.clearance == 2, "a good review raises your clearance")
	# Wired packages.
	var tinker: RobotAgent = sim.get_system("robot_tinker")
	var d0 := tinker._decay(sim)
	sw.installed_ids.append("firmware-stabilizer")
	_check(is_equal_approx(tinker._decay(sim), d0 * 0.5), "firmware-stabilizer halves software drift")


func _test_panel() -> void:
	var facility: Node = get_root().get_node("Facility")
	OSSettings.use_file("user://test_corp_os.json")
	facility.wipe_save("user://test_corp_save.json")
	var desk: Control = (load("res://os/desktop.tscn") as PackedScene).instantiate()
	desk.save_path = "user://test_corp_save.json"
	desk.skip_boot = true
	get_root().add_child(desk)
	await process_frame
	desk.set_anchors_preset(Control.PRESET_TOP_LEFT)
	desk.size = Vector2(1600, 900)
	desk.log_on()
	await process_frame
	await process_frame
	var panel = desk.hq_panel
	_check(panel != null and panel.list.get_child_count() >= 3, "the corkHQ panel shows corporate's messages")
	_check(panel.position.x > 1000 and panel.position.y < 40, "pinned in the top-right corner (%s)" % panel.position)
	_check(panel.find_children("*", "Button", true, false).is_empty(), "with no buttons: no close, no minimise")
	_check(panel.get_index() > desk.window_layer.get_index(), "above every window")
	var hq: CorkHQ = facility.sim.get_system("hq")
	hq.post(facility.sim, "Test", "notice", "Hello")
	await process_frame
	_check(panel._flash > 0.0 and panel.chime.playing or panel._flash > 0.0, "a new message flashes and chimes (no mute)")
	var app = desk.open_app("requisitions")
	_check(app != null and app.items.get_root() != null, "the Requisitions app opens")
	app.selected_item = "coolant_canister"
	var t0: float = facility.sim.time()
	app._order()
	_check(str(app.reply.text).contains("placed") and facility.sim.time() - t0 >= 119.9, "ordering from it costs facility time")
	desk.log_off()
	desk.free()
	facility.wipe_save("user://test_corp_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_corp_os.json"))


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1
