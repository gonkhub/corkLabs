@tool
# A robot's behaviour personality: how it weighs its options, how fast it
# burns power, how it takes orders. (Its *motion* personality is the
# RobotProfile; this is its *mind*.)
#
# Lives at robots/<id>/<id>_traits.tres. Open it in the Inspector; every
# value has a tooltip. Changes apply the next time the facility starts.
#
# How a robot decides (utility scores, like a mixer): every couple of
# facility seconds it scores each thing it could do between 0 and ~1.5 and
# does the highest. Needs, orders and personality are the faders.
class_name RobotTraits
extends Resource

@export var display_name := "Robot"

@export_group("Body and travel")
## Top speed along the rails, in m/s (facility time).
@export_range(0.1, 5.0, 0.05) var rail_speed := 0.8
## How wide the robot is, in meters. Routes narrower than this (a hatch, a
## duct) are closed to it.
@export_range(0.1, 6.0, 0.05) var width := 0.8
## How big the 3D robot is drawn (its baked motion scales with it).
@export_range(0.2, 6.0, 0.05) var visual_scale := 1.0

@export_group("Skills")
## How good it is at heavy work (lifting, hauling, clearing). 0 = useless, 1 = built for it.
## Poor skill = slower work and lower scores.
@export_range(0.0, 1.0, 0.05) var skill_heavy := 0.5
## How good it is at precise work (repairs, calibration, pod care).
@export_range(0.0, 1.0, 0.05) var skill_precise := 0.5
## How good it is at general work (inspections, cleaning, sorting).
@export_range(0.0, 1.0, 0.05) var skill_general := 0.7
## Work units done per facility second at skill 1.0.
@export_range(0.1, 5.0, 0.05) var work_speed := 1.0

@export_group("Power")
## Power used per facility second just being switched on (0-1 scale; 0.0002 = 1% every 50 s).
@export_range(0.0, 0.01, 0.00001) var drain_idle := 0.00003
## Extra power per second while travelling.
@export_range(0.0, 0.01, 0.00001) var drain_move := 0.00012
## Extra power per second while working.
@export_range(0.0, 0.01, 0.00001) var drain_work := 0.00018
## Power gained per second on a dock.
@export_range(0.0, 0.05, 0.0001) var charge_rate := 0.0012
## Below this it drops everything (even orders) to recharge.
@export_range(0.0, 0.5, 0.01) var power_reserve := 0.15
## Once charging, it stays on the dock until it reaches this.
@export_range(0.3, 1.0, 0.01) var charge_until := 0.95

@export_group("Software stability")
## Stability lost per idle second (0-1 scale). Robots think the work keeps
## THEM running; standing around makes their software drift.
@export_range(0.0, 0.01, 0.00001) var stability_decay := 0.0004
## Stability regained per second of work.
@export_range(0.0, 0.01, 0.00001) var stability_from_work := 0.001
## Stability gained on finishing a job.
@export_range(0.0, 1.0, 0.01) var stability_per_job := 0.25
## Stability lost when an order makes it drop what it wanted to do.
@export_range(0.0, 0.2, 0.005) var order_stress := 0.02
## How far low stability turns into independence: orders count for less,
## choices get erratic, errant behaviour creeps in. 0 = stays obedient however unstable.
@export_range(0.0, 1.0, 0.05) var independence := 0.6
## Resistance to critical errors (crashes, glitches) when stability is critical.
@export_range(0.0, 1.0, 0.05) var error_resistance := 0.3
## How willing it is, at critical stability, to break things so there's work to do.
@export_range(0.0, 1.0, 0.05) var sabotage_tendency := 0.4

@export_group("Orders")
## How much a supervisor's order adds to a job's score. High = obedient.
@export_range(0.0, 1.5, 0.05) var obedience := 0.6
## Refuses ordered work it's worse than this at ("not built for that").
@export_range(0.0, 1.0, 0.05) var refuse_below_skill := 0.2

@export_group("Deciding")
## Facility seconds between rethinks.
@export_range(0.5, 30.0, 0.5) var think_interval := 2.0
## Bonus for sticking with what it's doing, so it doesn't flip-flop.
@export_range(0.0, 0.5, 0.01) var commitment := 0.1
## How much it cares about travel distance (0 = not at all, 1 = strongly prefers nearby work).
@export_range(0.0, 1.0, 0.05) var distance_aversion := 0.4

@export_group("Voice")
## Colour of its words in the camera feeds.
@export var speech_color := Color(0.8, 0.9, 1.0)
## Voice blips: base pitch in Hz (low = big machine).
@export_range(40.0, 2000.0, 1.0) var voice_pitch := 440.0
## How much each blip's pitch wanders (0 = monotone).
@export_range(0.0, 1.0, 0.01) var voice_variation := 0.25
## Letters revealed (and blipped) per second.
@export_range(5.0, 60.0, 1.0) var voice_speed := 22.0
## Blip shape: "square" (buzzy), "sine" (soft), "saw" (harsh), "noise" (static).
@export_enum("square", "sine", "saw", "noise") var voice_wave := "square"
## Minimum facility seconds between things it says on its own.
@export_range(0.0, 600.0, 1.0) var chatter_cooldown := 45.0
## How chatty it is (0 = only speaks when it must, 1 = talks a lot).
@export_range(0.0, 1.0, 0.05) var chattiness := 0.5

@export_group("Animation")
## Clips to play while working, by job skill ("heavy", "precise", "general").
## Missing = any act_* clip.
@export var work_clips := {}


func skill(kind: String) -> float:
	match kind:
		"heavy": return skill_heavy
		"precise": return skill_precise
	return skill_general


## robots/<id>/<id>_traits.tres, or plain defaults if the robot has none.
static func load_for(robot_id: String) -> RobotTraits:
	var path := "res://robots/%s/%s_traits.tres" % [robot_id, robot_id]
	if ResourceLoader.exists(path):
		return load(path) as RobotTraits
	var t := RobotTraits.new()
	t.display_name = robot_id.capitalize()
	return t
