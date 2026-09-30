# corkLabs

Rail-robot facility game, with a VR puppeteering pipeline: you perform robots
with a Quest 3 (head + hands + controller inputs), and the performances are
baked into ordinary Godot animations.

**Core rule: takes are the source of truth.** A take is the raw recording of
what your head, hands, triggers, sticks and buttons did. Animations are
generated from takes and can be regenerated at any time: when a robot's
model changes, when its personality is retuned, when you add a new robot.
Nothing ever needs re-recording because the art changed.

```
Quest 3 ──► Recorder (VR) ──► take (.res) ──► cleanup ──► robot profile ──► baked clip ──► AnimationTree in game
             mirror robot,       raw data       trim,       gaze cascade,     joint tracks     idles + actions,
             play-along,         never edited   smooth,     arm IK, springs,  per robot        rail travel + sway
             punch-in                           loop        grippers, face                     added at runtime
```

First-time headset setup: see [SETUP.md](SETUP.md).
Premise and design decisions: [docs/DESIGN.md](docs/DESIGN.md).
Current status, open work and next steps: [docs/ROADMAP.md](docs/ROADMAP.md).

## Scenes

| Scene | Run with | What it's for |
| --- | --- | --- |
| `recorder/recorder.tscn` | **F5** (main scene), headset on | Perform, record, replay, punch-in |
| `game/robot_lab.tscn` | open it, **F6** | Compare any take on every robot side by side, on your monitor |
| `game/demo_facility.tscn` | open it, **F6** | The facility simulation seen through security cameras: robots pick their own work, you give orders |
| `recorder/hello_vr.tscn` | open it, **F6** | Phase 1 headset test (cubes + input readouts) |

Robot Lab and the demo run on the monitor. Because VR is on for the whole
project, they restart themselves once with VR off (`game/flat_screen.gd`).
The restarted game isn't attached to the editor, so its prints and errors go
to `%APPDATA%\Godot\app_userdata\corkLabs\logs\godot.log`, not the Output
panel, and you close it with its window's X rather than the editor's Stop button.

## Recording (in the headset)

X/Y/A/B are controls only while *not* recording. During a take they're
performance inputs (blink, flash, ...).

| Button | Does |
| --- | --- |
| Left **MENU** | 3-2-1 countdown (stand on the orange mark, look ahead: it measures your eye height), record, press again to stop |
| Left **X** | Choose the robot you're performing for (cycles through `robots/`, then "cubes only") |
| Left **Y** | Play-along on/off: your previous take plays on its robot beside you while you record the next |
| Left **stick click** | Punch-in: off → right arm → left arm → head → face. Re-perform just that part over your last take |
| Right **A** | Replay the last take on the robot / back to live mirror |
| Right **B** | Mirror view (robot faces you like a reflection) / behind view |
| Right **stick click** | Show/hide the cyan ghost cubes (raw recording) |
| **Space** (keyboard) | Same as MENU |

**What each input does on a robot** (during a take):

| Input | Robot |
| --- | --- |
| Head position / rotation | Body or core drifts and turns (slow), head on neck (medium), eye (fast): the "gaze cascade" |
| Hand position / rotation | Arm reaches (IK), wrist/tool copies your wrist |
| Trigger | Claw closes |
| Grip | Tinker: tool head spins. Hauler: claws clamp hard |
| Right stick | Eye looks around |
| Left stick | Down closes the eyelid, left/right changes lens size |
| A / X | Blink |
| B / Y | Eye flash |

When a robot is chosen, every take is saved to `takes/`, cleaned up, baked
into `animations/<robot>/`, and replayed on the robot straight away.

## Naming takes

When you stop a run that recorded takes, the editor opens **Name your new
takes**, listing every take that still has its automatic `take_<date>` name
(also available any time from the Takes panel's **Name takes...** button).
For each take: **Preview** it in Robot Lab, pick a type, type a name, keep
or discard. **Save names** then:

| Type | Clip name | Used as |
| --- | --- | --- |
| `idle` | `idle_scan` | looping idle (loop is ticked automatically) |
| `act` | `act_weld_panel` | action, `play_action("act_weld_panel")` |
| `cs` | `cs_intro_03` | cutscene performance |
| (none) | `whatever` | anything else |

- the take moves to `takes/<robot>/<clip>.res`
- the clip is baked to `animations/<robot>/<clip>.res` and added to the robot's library (the old timestamp clip is removed)
- punch-in raw recordings follow their comp into `takes/<robot>/sources/`
- duplicate names get `_2`, `_3`...
- discarded takes move to `takes/_discarded/` (delete that folder yourself when sure)

Names are cleaned to lower_snake_case ("Weld Panel!" → `weld_panel`).
Leave a name blank to decide later.

## At the desk

**Takes panel** (editor, top-left dock next to Scene/Import):
pick a take → set its robot, **clip name** (`idle_...` loops as an idle,
anything else plays as an action), loop, trims and smoothing → **Save + Bake**.
**Bake all** rebakes every take (do this after changing a robot or profile).
**Inspector** shows every setting of the take and its cleanup recipe.

**Tuning a robot's personality:** open `robots/<name>/<name>_profile.tres`
in the Inspector. Every value has a tooltip. The big ones:

| Setting | Heavy (Hauler) | Precise (Tinker) |
| --- | --- | --- |
| Body frequency / damping | 1.2 Hz / 0.5: sluggish, overshoots | 3 Hz / 0.85: quick, settles |
| Hand frequency / damping | 1.6 / 0.55 | 5 / 0.9 |
| Reach scale | 1.8× | 0.9× |
| Amplitude | 0.8 (stoic) | 1.15 (curious) |
| Retime | 1.25× slower (feels bigger) | 1.0 |

Then check it in **Robot Lab** (F6), and **Bake all** when happy.

## Facility time

Facility time **only moves when the player acts**, like Disco Elysium's clock.
Every player action goes through one call:

```gdscript
Facility.act("dialogue_line", "Tinker: status report")   # costs 1 facility minute
Facility.spend(900.0, "Hauler clears the jam")            # or any exact amount
```

and the facility (robots, scheduled events, shifts) plays out through exactly
that much time. Costs live in `Facility.COST` (`game/sim/facility.gd`):
dialogue line 1 min, choice 2 min, interaction 5 min, task 15 min.
Animations keep running in real time; the facility's *state* waits for you.

Closing the game saves it; opening it resumes at the exact saved moment. The
corkLabs OS clock shows facility time, never the real clock. A new facility
starts at Day 1 05:55 (first shift at 06:00).

| Piece | File | Job |
| --- | --- | --- |
| `FacilitySim` | `game/sim/facility_sim.gd` | The clock (0.1 s ticks), systems, seeded randomness, save/load. Same save + same actions = same outcome |
| `EventScheduler` | `game/sim/event_scheduler.gd` | Events booked at exact facility times; ties fire in booking order |
| `FacilityLog` | `game/sim/facility_log.gd` | The journal: a timestamped line for everything that happens |
| `Facility` (autoload) | `game/sim/facility.gd` | Session start/save, `spend()` / `act()`, `clock_text()` |
| `ShiftSchedule` | `game/sim/shift_schedule.gd` | First real system: Day/Swing/Night shifts, and a template for new systems |

**Writing a system** (robots, pipes, pods...): any object with `sim_id`,
`sim_tick(sim, dt)`, and optionally `sim_start`, `sim_event`, `sim_save`,
`sim_load`. See `shift_schedule.gd`. Pass it to `Facility.start_session([...])`.

**Dev panel: F1** in any scene with a running facility (the demo has one).
**F2** flips pages: overview (clock, booked events, journal), robots (what
each robot is doing, its needs, and its top scores with the reason), full
journal. F5 one tick, F6 +1 min (Shift +1 h), F7 +15 min, F8 wipe the save,
F9 post a random job.

## Robots in the facility

Each robot is a facility system (`RobotAgent`, `game/sim/robot_agent.gd`)
with its own mind. The 3D robot only *shows* it (`RobotView`): when facility
time jumps, the robot glides along its rail to where the sim says it is and
keeps performing what it's doing (work clips at a job, idles otherwise).

**Needs**

| Need | Goes down | Goes up | When it runs low |
| --- | --- | --- | --- |
| **Power** | always a little; more moving, most working | on its dock | below its reserve it drops everything to recharge; at 0 it stalls and limps on emergency cells |
| **Purpose** | standing idle (robots think the work keeps *them* running) | working, and a jump for each finished job | "restless", then "uneasy": hungrier for work, and eventually it wanders the rail looking for some |

**Deciding: utility scores, like a mixer.** Every couple of facility seconds
a robot scores everything it could do (each reachable job, recharge, stand
by, wander) and does the best. Job scores come from priority × skill ×
distance × power × hunger for purpose. The F1 robots page shows the top scores
and the reason; every change of mind goes in the journal with the runner-up:

```
06:55  Hauler: work #7 Replace fuse (0.60: high priority, precise skill 35%, 0.0 m away); next best stand by (0.34)
```

**Orders are a strong nudge, not a command.** `agent.give_order(sim, "job", id)`
(or `"recharge"`, `"standby"`, `"cancel"`) adds the robot's `obedience` to
that option. Usually it wins, and the robot says "On it." But below its power
reserve it recharges first, it refuses work it's hopeless at ("No. 'Clear
debris' is heavy work; I'm not built for it."), and an uneasy robot finds it
hard to stand still. Every answer goes in the journal.

**Personality** lives in `robots/<id>/<id>_traits.tres` (open it in the
Inspector; every value has a tooltip): rail speed, skills (heavy / precise /
general), power drain and charge, restlessness, obedience, when it refuses,
how often it rethinks, and which clips it plays for each kind of work.

| | Hauler | Tinker |
| --- | --- | --- |
| Skills | heavy 100%, precise 35% | precise 100%, heavy 20% (refuses heavy orders) |
| Rail speed | 0.5 m/s | 0.9 m/s |
| Restlessness | low (stoic) | high (curious, fidgety) |
| Obedience | high | lower |

**The floor plan** (`game/sim/facility_setup.gd`): rails and stations in
meters along them, the same numbers the 3D rails use. Tinker's loop has its
dock, the pods, the relay panel and a workbench; Hauler's straight rail has
its dock and three bays. A robot only reaches stations on its own rail.
`FacilitySetup.systems()` is the whole standard facility; every gameplay
scene starts its session with it.

**The work board** (`WorkBoard`, `game/sim/work_board.gd`): jobs with a
title, skill, station, amount of work, priority and progress. A robot claims
a job while it's on it; if it walks away the job goes back on the board with
its progress kept. A finished job fires a `job_done` event, so whatever posted
it can react.

**The demo** is a bare-bones supervisor console: Q select robot, O order it
to take the most urgent job it can reach, R recharge, S stand by, X cancel,
W wait 5 minutes. Orders cost facility time (a choice, 2 min).

## Folder map

| Folder | Contents |
| --- | --- |
| `recorder/` | VR recorder scene, `PerformanceFrame` (one moment), `PerformanceTake` (a recording) |
| `pipeline/` | Cleanup (`take_cleanup.gd`, `cleanup_recipe.gd`), baking (`baker.gd`), comping (`take_comp.gd`), springs, filters |
| `robots/` | One folder per robot: scene + rig script + profile. `robot_rig.gd` is the shared base |
| `takes/` | Your recordings (keep these!). `takes/demo/` = procedural demo takes, delete any time |
| `animations/` | Baked clips + one `AnimationLibrary` per robot (regenerated by baking) |
| `game/` | `RobotActor` (plays clips via AnimationTree), `RailRider` (rail travel + pendulum sway), `RobotView` (3D robot follows its sim self), demo + lab scenes |
| `game/sim/` | The facility simulation: clock, scheduler, journal, layout, work board, robot agents and traits |
| `addons/corklabs_pipeline/` | The editor Takes panel |
| `tools/` | Command-line tools (bake all, demo takes, screenshots, test runner) |
| `tests/` | Automated tests, no headset needed |

## Using robots in the game

```
Path3D (the rail)
└── PathFollow3D  + rail_rider.gd       travel_to(meters), max_speed, acceleration, swing
    └── Swing                           (pendulum pivot, driven by RailRider)
        └── Node3D + robot_actor.gd     robot_id = "hauler"
```

`RobotActor` loads the robot and its clip library, loops `idle*` clips
(crossfading to a random different idle each time), and
`play_action("act_weld")` plays any clip over the idle with fades.
See `game/demo_director.gd` for a working example.

## Adding a robot

1. Copy `robots/tinker/` (core-bot, telescoping arms) or `robots/hauler/`
   (hanging body, neck, two-segment arms) to `robots/<newname>/`, and rename
   the three files to `<newname>.tscn`, `<newname>_rig.gd`, `<newname>_profile.tres`.
2. Fix the paths inside the `.tscn` (script + profile) and the profile's
   `display_name`.
3. Change the shapes. Node names the rig script looks up must stay (or edit
   `_bind()` in the rig script). Arm segment lengths are read from the scene.
4. It shows up automatically in the recorder (Left X), Robot Lab and the
   Takes panel.

The rig must extend `RobotRig`, pose its joints in `drive()`, and list the
joints to bake in `baked_nodes()`. The base class has the shared maths
(springs, gaze helpers, two-bone IK, face envelopes).

## Tools and tests

```
powershell -File tools\run_tests.ps1                       # all tests, no headset
Godot --headless --xr-mode off --path . --script res://tools/bake_all.gd
Godot --headless --xr-mode off --path . --script res://tools/make_demo_takes.gd
```

(`Godot` = the console build of your Godot exe, e.g.
`Godot_v4.3-stable_win64_console.exe`.)

## Status and open questions

Built and tested without a headset (automated tests + screenshots). Not yet
tried in VR: the mirror robot, play-along and punch-in. Things to decide or
check once you've used it:

- [ ] Does the mirror view feel right, or is "behind" view easier to act with?
- [ ] Are the controller mappings right (grip = spin/clamp, sticks = face)?
- [ ] Bake happens when you press stop: is the hitch noticeable on long takes?
- [ ] Robot designs: Hauler's front view can still read a little leggy.
- [ ] Godot 4.3 → 4.6+ upgrade (needed later for Godot's new IK modifiers, for reactive IK).
