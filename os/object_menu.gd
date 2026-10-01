# What you can do to a thing you point at in a camera feed: the menu a left
# click opens (CamerasApp shows it at the cursor), and the one-line read-out
# the feed shows while you hover it. Ids come from FacilityWorld.pick:
#
#   robot:<id>   a unit: Talk, send it to a job, recharge, stand by, cancel its
#                order, diagnose, book a service, remote reboot; a seized
#                unit: send someone to reboot it by hand
#   <device>     a pipe, filter, pod, the relay, a door, a camera, the
#                uplink...: order maintenance (Dispatch picks the unit), call
#                it off, make it urgent; with no part in stock: order one,
#                express one, or patch it without; inspect; pipes: pump in
#                a coolant canister (hangar: the coolant feed, the compactor);
#                send a unit to inspect it (it reports back)
#   bench        the workbench: crated units to activate
#
# Every entry: {"text", "disabled", "tip", "act": Callable -> String (what
# happened, shown in the Cameras app)} or {"sep": true}; "talk": true opens
# the conversation instead; "sub": [entries] is a submenu.
class_name ObjectMenu
extends RefCounted


## Hover text for a thing.
static func describe(sim: FacilitySim, id: String) -> String:
	if sim == null:
		return ""
	if id.begins_with("robot:"):
		var bot := sim.get_system("robot_" + id.trim_prefix("robot:")) as RobotAgent
		if bot == null:
			return ""
		var text := "%s: %s\npower %d%%   stability %d%% %s   wear %d%%" % [bot.display_name().to_upper(), bot.doing_text(sim),
			_pct(bot.power), _pct(bot.stability), bot.stability_state, _pct(bot.wear)]
		if Story.knows(sim, "met:" + RobotTraits.model_of(bot.robot_id)) or Story.knows(sim, "met:" + bot.robot_id):
			text += "\ntrust " + trust_pips(Story.knowledge(sim).value("trust:" + bot.robot_id))
		var r := _request_of(sim, bot)
		if not r.is_empty():
			text += "\nwants a word (it'll ask while you watch it)"
		elif bot.own_will():
			text += "\n(unstable: choosing its own work)"
		return text
	if id.begins_with("prop:"):
		var props := sim.get_system("props") as UnitProps
		var it := props.item(id.trim_prefix("prop:")) if props else {}
		if it.is_empty():
			return ""
		var held := str(it.held_by)
		return "%s: %s" % [str(it.name).capitalize(), ("with " + held.capitalize()) if not held.is_empty() else ("at the " + str((sim.get_system("layout") as FacilityLayout).station(str(it.at)).get("name", it.at)).to_lower())]
	if id == "bench":
		var req := sim.get_system("requisitions") as Requisitions
		var crated: Array = req.crated_units() if req else []
		return "Workbench" + ("\n%d crated unit%s waiting to be activated" % [crated.size(), "" if crated.size() == 1 else "s"] if not crated.is_empty() else "")
	var plant := sim.get_system("plant") as FacilityPlant
	var d := plant.device(id) if plant else {}
	if d.is_empty():
		return id
	var text := plant.device_text(id).get_slice("  job", 0).strip_edges()
	text = "%s: %s" % [d.name, text.substr(str(d.name).length()).strip_edges()]
	var board := sim.get_system("work") as WorkBoard
	var job: Dictionary = board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if WorkBoard.active(job):
		text += "\n" + job_state(sim, job)
	if d.kind == "pipe":
		text += "\ncoolant %d%%" % _pct(plant.coolant)
	return text


## Trust as pips: one per point, a half for a half.
static func trust_pips(t: float) -> String:
	var out := ""
	for i in int(Knowledge.TRUST_MAX):
		out += "●" if t >= i + 1.0 else ("◐" if t >= i + 0.5 else "○")
	return out


## What the hover card on a camera feed shows about a thing:
## {"title", "color", "chips": [[text, Color]], "lines": [text], "bars": [[label, 0-1, Color]]}.
static func info(sim: FacilitySim, id: String) -> Dictionary:
	var out := {"title": "", "color": OSTheme.ACCENT, "chips": [], "lines": [], "bars": []}
	if sim == null:
		return out
	if id.begins_with("robot:"):
		var bot := sim.get_system("robot_" + id.trim_prefix("robot:")) as RobotAgent
		if bot == null:
			return out
		out.title = bot.display_name().to_upper()
		out.color = OSTheme.category_color(bot.robot_id)
		var state_col := {"stable": OSTheme.ACCENT, "drifting": OSTheme.WARN, "unstable": OSTheme.ALARM, "critical": OSTheme.ALARM}
		if bot.offline():
			out.chips.append([str(bot.activity.kind).to_upper(), OSTheme.ALARM])
		else:
			out.chips.append([bot.stability_state.to_upper(), state_col.get(bot.stability_state, OSTheme.TEXT)])
		if bot.activity.kind == "link":
			out.chips.append(["ON THE LINK", OSTheme.INFO])
		if not _request_of(sim, bot).is_empty():
			out.chips.append(["ASKING", OSTheme.WARN])
		var props := sim.get_system("props") as UnitProps
		var held := props.holding(bot.robot_id) if props else ""
		if not held.is_empty():
			out.chips.append(["HOLDING " + str(props.item(held).name).trim_prefix(bot.display_name() + "'s ").to_upper(), OSTheme.TEXT_DIM])
		var doing := bot.doing_text(sim)
		out.lines.append(doing.left(1).to_upper() + doing.substr(1))
		out.bars.append(["Power", bot.power, OSTheme.ACCENT if bot.power > 0.35 else OSTheme.WARN])
		out.bars.append(["Stability", bot.stability, OSTheme.ACCENT if bot.stability >= 0.6 else (OSTheme.WARN if bot.stability >= 0.35 else OSTheme.ALARM)])
		out.bars.append(["Condition", 1.0 - bot.wear, OSTheme.ACCENT if bot.wear < 0.4 else (OSTheme.WARN if bot.wear < 0.5 else OSTheme.ALARM)])
		if Story.knows(sim, "met:" + RobotTraits.model_of(bot.robot_id)) or Story.knows(sim, "met:" + bot.robot_id):
			out.lines.append("Trust " + trust_pips(Story.knowledge(sim).value("trust:" + bot.robot_id)))
		return out
	if id.begins_with("prop:") or id == "bench":
		out.title = describe(sim, id).get_slice("\n", 0).get_slice(":", 0).to_upper()
		out.lines.append(describe(sim, id).substr(describe(sim, id).find(":") + 1).strip_edges())
		return out
	var plant := sim.get_system("plant") as FacilityPlant
	var d := plant.device(id) if plant else {}
	if d.is_empty():
		return out
	out.title = str(d.name).to_upper()
	var k: Dictionary = FacilityPlant.KINDS[d.kind]
	if d.fault:
		out.chips.append([("DISABLED" if d.get("disabled", false) else ("NO POWER" if d.get("unpowered", false) else "FAULT")), OSTheme.ALARM])
	var board := sim.get_system("work") as WorkBoard
	var job: Dictionary = board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if WorkBoard.active(job):
		if job.status == "claimed":
			out.chips.append(["IN HAND", OSTheme.ACCENT])
		elif job.get("requested", false):
			out.chips.append(["REQUESTED", OSTheme.INFO])
		elif not board.missing_part(sim, job).is_empty():
			out.chips.append(["NO PART", OSTheme.WARN])
		else:
			out.chips.append(["NEEDS ORDERING", OSTheme.WARN])
	out.lines.append(plant.device_text(id).get_slice("  job", 0).substr(str(d.name).length()).strip_edges().capitalize())
	if k.has("drift"):
		var v := float(d.value)
		var label: String = {"pod": "Sync", "filter": "Clean", "waste": "Room", "compactor": "Room", "rails": "Clean"}.get(d.kind, "Condition")
		out.bars.append([label, v, OSTheme.ACCENT if v >= 0.6 else (OSTheme.WARN if v >= 0.3 else OSTheme.ALARM)])
	if WorkBoard.active(job):
		out.lines.append(job_state(sim, job))
		if job.status == "claimed":
			out.bars.append(["Job", board.fraction_done(job), OSTheme.INFO])
	if d.kind in ["pipe", "feed"]:
		out.bars.append(["Coolant", plant.coolant, OSTheme.ACCENT if plant.coolant >= 0.5 else OSTheme.WARN])
	var rep: Dictionary = plant.reports.get(id, {})
	if not rep.is_empty():
		out.lines.append("Inspected %s by %s" % [FacilitySim.format_clock(float(rep.t)), rep.by])
	return out


## "Hauler on it, 40%" / "queued" / "nobody asked" / "needs a part".
static func job_state(sim: FacilitySim, job: Dictionary) -> String:
	var board := sim.get_system("work") as WorkBoard
	if job.status == "claimed":
		return "%s: %s on it, %d%%" % [job.title, str(job.claimed_by).trim_prefix("robot_").capitalize(), roundi(board.fraction_done(job) * 100.0)]
	if job.get("requested", false):
		return "%s: requested, waiting for a free unit" % job.title
	var part := board.missing_part(sim, job)
	if not part.is_empty():
		return "%s: NEEDS %s (none in stock)" % [job.title, WorkBoard.part_name(sim, part).to_upper()]
	return "%s: nobody's been asked" % job.title


## The menu for a thing.
static func entries(sim: FacilitySim, id: String) -> Array[Dictionary]:
	if sim == null:
		return []
	if id.begins_with("robot:"):
		var bot := sim.get_system("robot_" + id.trim_prefix("robot:")) as RobotAgent
		return _robot(sim, bot) if bot else []
	if id == "bench":
		return _bench(sim)
	if id.begins_with("prop:"):
		return [_label(describe(sim, id))]
	return _device(sim, id)


# --- Units ----------------------------------------------------------------------------

static func _robot(sim: FacilitySim, bot: RobotAgent) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_label("%s: %s" % [bot.display_name().to_upper(), bot.doing_text(sim)]))
	var board := sim.get_system("work") as WorkBoard
	if bot.activity.kind == "seized":
		var job := _reboot_job(sim, bot)
		if job.is_empty():
			out.append(_label("Seized up: it will work itself free, eventually."))
		elif job.get("requested", false):
			out.append(_label("Manual reboot: " + job_state(sim, job)))
		else:
			var jid := int(job.id)
			out.append(_item("Send a unit to reboot it by hand", "", "Dispatch sends the best free unit (precise work). 5 min",
				func(): return str(Supervisor.request_job(jid).text)))
	var talk := _item("Talk", "No response: it's offline." if bot.offline() else "",
		"Open the unit link: it answers on camera. Conversing with units is against the Code of Conduct.")
	talk.talk = true
	out.append(talk)
	if not bot.offline():
		var jobs: Array[Dictionary] = []
		for j in board.open_jobs():
			var why := Dispatch.unfit(sim, bot, j)
			if why == "busy" or why == "needs to charge":
				why = ""   # an order overrides what it's doing
			if not str(j.claimed_by).is_empty() and str(j.claimed_by) != bot.sim_id:
				why = "%s is on it" % str(j.claimed_by).trim_prefix("robot_").capitalize()
			var part := board.missing_part(sim, j)
			if why.is_empty() and not part.is_empty():
				why = "no %s in stock" % WorkBoard.part_name(sim, part)
			if not why.is_empty():
				continue   # only the jobs it can actually take
			var jid := int(j.id)
			jobs.append(_item("%s (%s)" % [j.title, _station_name(sim, str(j.station))], "", "It goes now; the time passes while it works.",
				func(): return str(Supervisor.order(bot, "job", jid).reply)))
		if jobs.is_empty():
			jobs.append(_label("Nothing it can take right now."))
		out.append({"text": "Send to a job", "sub": jobs})
		out.append(_item("Recharge", "", "5 min", func(): return str(Supervisor.order(bot, "recharge").reply)))
		out.append(_item("Stand by", "", "5 min", func(): return str(Supervisor.order(bot, "standby").reply)))
		if not bot.order.is_empty():
			out.append(_item("Cancel its order", "", "5 min", func(): return str(Supervisor.order(bot, "cancel").reply)))
	out.append({"sep": true})
	out.append(_item("Diagnose (30 min)", "", "Reads it out properly and steadies it a little.", func(): return Supervisor.diagnose(bot)))
	var req := sim.get_system("requisitions") as Requisitions
	var servos := int(req.inventory.get("servo_bundle", 0)) if req else 0
	var booked := board.jobs.any(func(j): return str(j.source) == "service:" + bot.robot_id and WorkBoard.active(j))
	var service_why := "Already booked." if booked else ("No servo bundles in stock." if servos <= 0 else ("Its joints are fine." if bot.wear < 0.2 else ""))
	out.append(_item("Book a service (wear %d%%, %d servo bundle%s)" % [_pct(bot.wear), servos, "" if servos == 1 else "s"], service_why,
		"At its dock: uses a servo bundle, brings wear back down. 5 min", func():
			var sid := Supervisor.book_service(bot)
			return ("Service booked: job #%d." % sid) if sid >= 0 else ("No servo bundles in stock." if sid == -2 else "A service is already booked.")))
	if Supervisor.has_software("remote-reboot"):
		out.append(_item("Remote reboot" + (" (frees it)" if bot.activity.kind == "seized" else ""),
			"It's already offline." if bot.offline() and bot.activity.kind != "seized" else "",
			"Offline %d min, restores stability; frees a seized unit" % int(RobotAgent.REBOOT_TIME / 60.0),
			func(): return "Reboot sent." if Supervisor.reboot(bot) else "It can't be rebooted now."))
	return out


static func _reboot_job(sim: FacilitySim, bot: RobotAgent) -> Dictionary:
	var board := sim.get_system("work") as WorkBoard
	for j in board.open_jobs():
		if str(j.source) == "unit:" + bot.robot_id:
			return j
	return {}


# --- Devices --------------------------------------------------------------------------

static func _device(sim: FacilitySim, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var plant := sim.get_system("plant") as FacilityPlant
	var board := sim.get_system("work") as WorkBoard
	var req := sim.get_system("requisitions") as Requisitions
	var d := plant.device(id) if plant else {}
	if d.is_empty():
		return out
	out.append(_label(describe(sim, id).get_slice("\n", 0)))
	var k: Dictionary = FacilityPlant.KINDS[d.kind]
	var job: Dictionary = board.get_job(int(d.job)) if int(d.job) >= 0 else {}
	if WorkBoard.active(job):
		var jid := int(job.id)
		if job.get("requested", false):
			out.append(_label(job_state(sim, job)))
			out.append(_item("Call it off", "", "The unit stands down; an unused part goes back in stock. 5 min", func():
				Supervisor.cancel_request(jid)
				return "Called off."))
		else:
			var part := board.missing_part(sim, job)
			if part.is_empty():
				var uses := ""
				if job.has("part") and not job.get("part_used", false):
					uses = " (uses %s: %d in stock)" % [WorkBoard.part_name(sim, str(job.part)), int(req.inventory.get(str(job.part), 0)) if req else 0]
				out.append({"text": "Order maintenance" + uses, "sub": _units_for(sim, job, id, false)})
			else:
				var it := req.item(part) if req else {}
				out.append(_item("Order maintenance", "No %s in stock." % it.get("name", part), ""))
				out.append(_item("Order %s (%d cr, %d h)" % [it.get("name", part), int(it.get("price", 0)), int(it.get("hours", 0))], "",
					"Arrives as a crate your units bring in. 5 min", func(): return str(Supervisor.requisition(part, 1).text)))
				out.append(_item("Express %s (%d cr, about %d h)" % [it.get("name", part), roundi(int(it.get("price", 0)) * Requisitions.EXPRESS_COST),
					maxi(roundi(float(it.get("hours", 0)) * Requisitions.EXPRESS_TIME), 1)], "", "Couriered straight into stock. 5 min",
					func(): return str(Supervisor.requisition(part, 1, true).text)))
				out.append({"text": "Patch it without the part (won't hold long)", "sub": _units_for(sim, job, id, true)})
			if int(job.priority) < 3:
				out.append(_item("Make it urgent", "", "Critical priority: units put it first. 5 min", func():
					Supervisor.set_priority(jid, 3)
					return "Job #%d is critical now." % jid))
	elif d.kind == "feed":
		var cans := int(req.inventory.get("coolant_canister", 0)) if req else 0
		out.append(_item("Feed a coolant canister (%d in stock, coolant %d%%)" % [cans, _pct(plant.coolant)],
			"No coolant canisters in stock." if cans <= 0 else ("The reservoir is full." if plant.coolant >= 0.95 else ""),
			"Ogre lifts one into the loop: +%d%% coolant." % _pct(FacilityPlant.COOLANT_CANISTER), func(): return str(Supervisor.pump_coolant().text)))
	elif k.has("drift") and float(d.value) < 0.95:
		out.append({"text": "Order maintenance (early)", "sub": _units_for(sim, {"skill": FacilityPlant.KINDS[d.kind].skill, "station": d.station, "id": -1}, id, false)})
	else:
		out.append(_label("Nothing needs doing."))
	if d.kind == "pipe" and plant:
		out.append(_label("Coolant %d%%: top it up at the coolant feed in the hangar (Ogre)" % _pct(plant.coolant)))
	out.append({"sep": true})
	out.append({"text": "Send a unit to inspect it", "sub": _inspectors(sim, id)})
	var rep: Dictionary = plant.reports.get(id, {})
	if not rep.is_empty():
		out.append(_label("Last report (%s, %s): %s" % [rep.by, FacilitySim.format_clock(float(rep.t)), str(rep.text).get_slice("\n", 0)]))
	return out


# Which unit to send: every unit, the best free one first; the ones that
# can't, greyed out with why.
static func _units_for(sim: FacilitySim, job: Dictionary, device_id: String, makeshift: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in Dispatch.options(sim, job):
		var bot: RobotAgent = o.bot
		var why := str(o.why)
		var note := "%s %d%%" % [str(job.get("skill", "general")), roundi(float(o.fit) * 100.0)]
		if float(o.dist) >= 0.0:
			note += ", %d m" % roundi(float(o.dist))
		if why == "busy":
			note += ", busy: drops what it's doing"
		elif not why.is_empty():
			note += ": " + why
		if o.best:
			note += " (best)"
		var uid := bot.robot_id
		out.append(_item("%s (%s)" % [bot.display_name(), note], "" if why.is_empty() or why == "busy" else why.capitalize() + ".",
			"It goes now; the time passes while it works.", func(): return str(Supervisor.order_maintenance(device_id, makeshift, uid).text)))
	return out


# Who to send to look at something: anyone who can get there.
static func _inspectors(sim: FacilitySim, device_id: String) -> Array[Dictionary]:
	var plant := sim.get_system("plant") as FacilityPlant
	var d := plant.device(device_id)
	var out: Array[Dictionary] = []
	for o in Dispatch.options(sim, {"skill": "general", "station": d.station, "id": -1}):
		var bot: RobotAgent = o.bot
		var why := str(o.why)
		var note := "%d m" % roundi(float(o.dist)) if float(o.dist) >= 0.0 else ""
		if why == "busy":
			note += ", busy: drops what it's doing"
		elif not why.is_empty():
			note += (": " if not note.is_empty() else "") + why
		var uid := bot.robot_id
		out.append(_item("%s (%s)" % [bot.display_name(), note], "" if why.is_empty() or why == "busy" else why.capitalize() + ".",
			"It goes and looks, and reports back.", func(): return str(Supervisor.order_inspection(device_id, uid).text)))
	return out


static func _bench(sim: FacilitySim) -> Array[Dictionary]:
	var out: Array[Dictionary] = [_label("Workbench")]
	var req := sim.get_system("requisitions") as Requisitions
	var crated: Array = req.crated_units() if req else []
	for c in crated:
		var item_id := str(c.item)
		out.append(_item("Activate %s (%d in stock, %d min)" % [c.name, c.count, int(Supervisor.ACTIVATE_MINUTES)], "",
			"Unpack it, bolt it on, first boot.", func(): return str(Supervisor.activate_unit(item_id).text)))
	if crated.is_empty():
		out.append(_label("Nothing to activate."))
	return out


# --- Helpers --------------------------------------------------------------------------

static func _request_of(sim: FacilitySim, bot: RobotAgent) -> Dictionary:
	var reqs := sim.get_system("requests") as UnitRequests
	if reqs:
		for r in reqs.requests:
			if str(r.robot) == bot.robot_id:
				return r
	return {}


static func _item(text: String, disabled_why: String, tip: String, act := Callable()) -> Dictionary:
	return {"text": text, "act": act, "disabled": not disabled_why.is_empty(), "tip": disabled_why if not disabled_why.is_empty() else tip}


static func _label(text: String) -> Dictionary:
	return {"text": text, "disabled": true, "label": true, "tip": ""}


static func _station_name(sim: FacilitySim, station: String) -> String:
	var layout := sim.get_system("layout") as FacilityLayout
	return str(layout.station(station).get("name", station)) if layout else station


static func _pct(x: float) -> int:
	return roundi(x * 100.0)
