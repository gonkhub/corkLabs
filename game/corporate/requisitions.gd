# Requisitions (sim_id "requisitions"): the supervisor's budget and orders.
#
#   funds      credits. Corporate allocates more at the end of every shift,
#              scaled by the shift's grade (CorkHQ review): a good shift
#              means a bigger budget.
#   catalog    game/corporate/catalog.txt: resources, replacement parts, new
#              robot models. Price, delivery time, whether corporate must
#              approve it, and what happens on delivery.
#   orders     placed -> "pending" (awaiting corporate approval, if the item
#              needs it; can be DENIED, refunded, if the rating is poor)
#              -> "in transit" -> "delivered". Every step is a corkHQ message.
#   inventory  delivered parts and crated units (placeholders for now; the
#              coolant canister is wired and tops up the coolant reservoir).
class_name Requisitions
extends RefCounted

const CATALOG_PATH := "res://game/corporate/catalog.txt"
const START_FUNDS := 1000
## Spare parts on the shelf when a new supervisor arrives: an order or two of
## each (and two coolant canisters to pump in when it runs low); not the week.
const START_STOCK := {"pipe_clamps": 6, "fuse_pack": 4, "filter_cartridges": 6, "actuator_kit": 2,
	"camera_module": 2, "servo_bundle": 2, "coolant_canister": 2}
## Budget allocated per shift for each grade.
const ALLOCATION := {"A": 900, "B": 700, "C": 500, "D": 300, "F": 100}
## Lowest grade at which corporate approves items that need approval.
const APPROVE_GRADES := ["", "A", "B", "C"]
## Facility seconds before corporate decides on an order that needs approval.
const REVIEW_TIME := Vector2(900.0, 3600.0)

var sim_id := "requisitions"
var funds := START_FUNDS
## [{"id", "category", "name", "price", "hours", "approval", "effect", "description"}]
var catalog: Array[Dictionary] = []
## {"id", "item", "qty", "cost", "status", "placed", "eta"}
var orders: Array[Dictionary] = []
var inventory := {}
var next_id := 1


func _init() -> void:
	for row in DataTable.read(CATALOG_PATH, PackedStringArray(["id", "category", "name", "price", "hours", "approval", "effect", "description"])):
		row.price = int(row.price)
		row.hours = float(row.hours)
		row.approval = row.approval.to_lower() == "yes"
		catalog.append(row)


func item(id: String) -> Dictionary:
	for c in catalog:
		if c.id == id:
			return c
	return {}


func categories() -> PackedStringArray:
	var out := PackedStringArray()
	for c in catalog:
		if not out.has(c.category):
			out.append(c.category)
	return out


func get_order(id: int) -> Dictionary:
	for o in orders:
		if o.id == id:
			return o
	return {}


## Places an order. Returns {"ok", "text", "order"}; corkHQ confirms it.
## Express costs this much more, arrives in this share of the time, and is
## couriered straight to the workshop (no crate for the units to bring in).
const EXPRESS_COST := 1.75
const EXPRESS_TIME := 0.35


func place(sim: FacilitySim, item_id: String, qty := 1, express := false) -> Dictionary:
	var it := item(item_id)
	if it.is_empty():
		return {"ok": false, "text": "No such item."}
	qty = maxi(qty, 1)
	var cost: int = roundi(it.price * qty * (EXPRESS_COST if express else 1.0))
	if cost > funds:
		return {"ok": false, "text": "Insufficient funds: %d cr needed, %d cr available." % [cost, funds]}
	funds -= cost
	var o := {"id": next_id, "item": item_id, "qty": qty, "cost": cost, "placed": sim.time(), "eta": -1.0,
		"status": "pending" if it.approval else "in transit", "express": express}
	next_id += 1
	orders.append(o)
	var hq := _hq(sim)
	if it.approval:
		sim.schedule_in(sim.rng.randf_range(REVIEW_TIME.x, REVIEW_TIME.y), "requisition_review", {"order": o.id})
		if hq:
			hq.post(sim, "Procurement", "order", "Requisition #%d received: %dx %s (%d cr). Pending corporate approval." % [o.id, qty, it.name, cost])
	else:
		_ship(sim, o)
	return {"ok": true, "text": "Requisition #%d placed." % o.id, "order": o}


## End-of-shift allocation for `grade`. Returns the amount added.
func allocate(_sim: FacilitySim, grade: String) -> int:
	var amount: int = ALLOCATION.get(grade, 300)
	funds += amount
	return amount


func _ship(sim: FacilitySim, o: Dictionary) -> void:
	var it := item(o.item)
	o.status = "in transit"
	o.eta = sim.time() + float(it.hours) * 3600.0 * (EXPRESS_TIME if o.get("express", false) else 1.0)
	sim.schedule(o.eta, "requisition_delivery", {"order": o.id})
	var hq := _hq(sim)
	if hq:
		hq.post(sim, "Procurement", "order", "Requisition #%d confirmed: %dx %s shipped. Arrives %s." % [
			o.id, o.qty, it.name, FacilitySim.format_time(o.eta)])


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	var o := get_order(int(data.get("order", -1)))
	if o.is_empty():
		return
	var it := item(o.item)
	var hq := _hq(sim)
	match event_name:
		"requisition_review":
			if o.status != "pending":
				return
			var grade := hq.grade if hq else ""
			if APPROVE_GRADES.has(grade):
				if hq:
					hq.post(sim, "Procurement", "order", "Requisition #%d APPROVED." % o.id)
				_ship(sim, o)
			else:
				o.status = "denied"
				funds += int(o.cost)
				if hq:
					hq.post(sim, "Procurement", "order", "Requisition #%d DENIED: your rating (%s) does not justify %s. %d cr returned." % [
						o.id, grade, it.name, o.cost])
		"requisition_delivery":
			if o.status != "in transit":
				return
			o.status = "delivered"
			_deliver(sim, o, it)
			if hq:
				hq.post(sim, "Logistics", "order", "Requisition #%d delivered: %dx %s.%s" % [o.id, o.qty, it.name,
					"" if str(it.effect).begins_with("coolant:") else " Crated in the deep stacks; your units will bring it in."])


# What arrives: coolant is pumped straight into the reservoir; everything else
# is a crate in the deep stacks that the units bring in (FacilityPlant: Ogre,
# a rail unit, Tinker) and that's in stock once it's unpacked.
func _deliver(sim: FacilitySim, o: Dictionary, it: Dictionary) -> void:
	var effect: String = it.effect
	var plant := sim.get_system("plant") as FacilityPlant
	if effect.begins_with("coolant:"):
		if plant:
			plant.coolant = minf(plant.coolant + float(effect.trim_prefix("coolant:")) * int(o.qty), 1.0)
			sim.note("plant", "Coolant topped up to %d%%" % roundi(plant.coolant * 100.0))
		return
	if plant and not o.get("express", false):
		o.status = "crated"
		plant.receive_crate(sim, int(o.id), "%dx %s" % [int(o.qty), it.name])
	else:
		# Express is couriered straight to the workshop: no crate, no units needed.
		unpacked(sim, int(o.id))


## Is this a part that repairs or services use up (FacilityPlant.KINDS, services)?
static func used_for_repairs(item_id: String) -> bool:
	if item_id == "servo_bundle":
		return true
	for k in FacilityPlant.KINDS:
		if str(FacilityPlant.KINDS[k].get("part", "")) == item_id:
			return true
	return false


## Crated units in stock that can be activated: [{"item", "name", "model", "count"}].
func crated_units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in catalog:
		if str(it.effect).begins_with("robot:") and int(inventory.get(it.id, 0)) > 0:
			out.append({"item": it.id, "name": it.name, "model": str(it.effect).trim_prefix("robot:"), "count": int(inventory[it.id])})
	return out


## Activates a crated unit from stock: a new unit on the workbench's rail,
## on fresh firmware (fully stable, half charged). Returns {"ok", "text", "bot"}.
## Only models the facility has firmware for (a robots/<model> folder) boot.
func activate(sim: FacilitySim, item_id: String) -> Dictionary:
	var it := item(item_id)
	if it.is_empty() or not str(it.effect).begins_with("robot:") or int(inventory.get(item_id, 0)) <= 0:
		return {"ok": false, "text": "No crated unit like that in stock."}
	var model := str(it.effect).trim_prefix("robot:")
	if not ResourceLoader.exists("res://robots/%s/%s_traits.tres" % [model, model]):
		return {"ok": false, "text": "No firmware for %s on this facility. The crate stays shut." % it.name}
	var n := 2
	while sim.get_system("robot_%s%d" % [model, n]) != null:
		n += 1
	var layout := sim.get_system("layout") as FacilityLayout
	var st: Dictionary = layout.station("bench") if layout else {}
	var bot := RobotAgent.new("%s%d" % [model, n], null, str(st.get("segment", "")), float(st.get("offset", 0.0)))
	bot.stability = 1.0
	bot.power = 0.5
	inventory[item_id] = int(inventory[item_id]) - 1
	sim.add_system(bot)
	bot.sim_start(sim)
	var hq := _hq(sim)
	if hq:
		hq.post(sim, "Unit Oversight", "notice", "New unit %s registered to your facility. Units are corporate property." % bot.display_name().to_upper())
	return {"ok": true, "text": "%s is online." % bot.display_name(), "bot": bot}


## The crate's been unpacked in the workshop: it's in stock.
func unpacked(sim: FacilitySim, order_id: int) -> void:
	var o := get_order(order_id)
	if o.is_empty() or o.status == "unpacked":
		return
	var it := item(o.item)
	o.status = "unpacked"
	inventory[o.item] = int(inventory.get(o.item, 0)) + int(o.qty) * pack_size(it)
	var board := sim.get_system("work") as WorkBoard
	if board:
		board.parts_arrived(sim, o.item)
	var hq := _hq(sim)
	if hq:
		hq.post(sim, "Logistics", "order", "Requisition #%d unpacked in the workshop: %dx %s in stock." % [o.id, o.qty, it.name])
	if str(it.effect).begins_with("robot:"):
		sim.note("requisitions", "%s unpacked in the workshop, awaiting activation" % it.name)


## How many a catalogue item holds: "Fuse pack (x4)" -> 4.
static func pack_size(it: Dictionary) -> int:
	var name := str(it.get("name", ""))
	var i := name.find("(x")
	if i < 0:
		return 1
	var n := name.substr(i + 2).get_slice(")", 0)
	return maxi(int(n), 1) if n.is_valid_int() else 1


func sim_start(_sim: FacilitySim) -> void:
	inventory = START_STOCK.duplicate()


## Night procurement: between shifts, corkHQ's automated buyer orders what
## the facility is visibly short of (parts that stopped jobs, coolant when
## it's low), express, and charges your budget. Neglect costs money.
const NIGHT_BUY_EVERY := 3600.0
const NIGHT_COOLANT := 0.25
## The most night procurement spends in one night; past that, it patches.
const NIGHT_CAP := 300
var night_spent := 0
var night_patched := 0
var _night_acc := 0.0


func sim_tick(sim: FacilitySim, dt: float) -> void:
	var camp := sim.get_system("campaign") as Campaign
	if camp == null or camp.on_duty():
		_night_acc = 0.0
		return
	_night_acc += dt
	if _night_acc < NIGHT_BUY_EVERY - 0.001:
		return
	_night_acc = 0.0
	if camp.state != "off_duty":
		return
	var want: Array[String] = []
	var board := sim.get_system("work") as WorkBoard
	if board:
		for j in board.waiting_jobs(sim):
			if not want.has(str(j.part)):
				want.append(str(j.part))
	var plant := sim.get_system("plant") as FacilityPlant
	if plant and plant.coolant < NIGHT_COOLANT and int(inventory.get("coolant_canister", 0)) > 0:
		# A canister from stock first: Ogre feeds it in.
		if int(plant.device("coolant_feed").job) < 0 and board:
			var feed := Dispatch.job_for_device(sim, "coolant_feed")
			if not feed.is_empty():
				board.request(sim, int(feed.id))
				sim.note("requisitions", "Night procurement: a coolant canister from stock, for Ogre to feed in")
	elif plant and plant.coolant < NIGHT_COOLANT and not orders.any(func(o): return o.item == "coolant_canister" and o.placed > sim.time() - 12 * 3600.0):
		want.append("coolant_canister")   # one a night at most
	for item_id in want:
		# Already on its way by courier? (A crate stuck in the hangar doesn't count.)
		if orders.any(func(o): return o.item == item_id and o.status in ["pending", "in transit"]):
			continue
		var before := funds
		var r := place(sim, item_id, 1, true) if night_spent + roundi(int(item(item_id).get("price", 0)) * EXPRESS_COST) <= NIGHT_CAP else {"ok": false}
		if r.ok:
			night_spent += before - funds
			sim.note("requisitions", "Night procurement: %s (express, %d cr)" % [item(item_id).name, before - funds])
		elif board:
			# No budget: the night crew patches what's waiting for it instead.
			for j in board.waiting_jobs(sim):
				if str(j.part) == item_id:
					board.patch(sim, int(j.id))
					night_patched += 1


func _hq(sim: FacilitySim) -> CorkHQ:
	return sim.get_system("hq") as CorkHQ


func sim_save() -> Dictionary:
	return {"funds": funds, "orders": orders.duplicate(true), "inventory": inventory.duplicate(), "next_id": next_id,
		"night_spent": night_spent, "night_acc": _night_acc, "night_patched": night_patched}


func sim_load(d: Dictionary) -> void:
	funds = int(d.get("funds", START_FUNDS))
	next_id = int(d.get("next_id", 1))
	night_spent = int(d.get("night_spent", 0))
	night_patched = int(d.get("night_patched", 0))
	_night_acc = float(d.get("night_acc", 0.0))
	inventory = {}
	for k in d.get("inventory", {}):
		inventory[k] = int(d.inventory[k])
	orders.clear()
	for o in d.get("orders", []):
		var order: Dictionary = o.duplicate()
		order.id = int(order.id)
		order.qty = int(order.qty)
		order.cost = int(order.cost)
		order.placed = float(order.placed)
		order.eta = float(order.eta)
		orders.append(order)


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var open := orders.filter(func(o): return o.status in ["pending", "in transit"])
	return PackedStringArray(["REQUISITIONS  funds %d cr   %d open orders   stock %s" % [funds, open.size(), str(inventory)]])
