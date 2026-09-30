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
| `os/desktop.tscn` | **F5** (main scene) | **The game**: boots into the corkLabs OS, the supervisor's desktop |
| `recorder/recorder.tscn` | open it, **F6**, headset on | Perform, record, replay, punch-in |
| `game/robot_lab.tscn` | open it, **F6** | Compare any take on every robot side by side, on your monitor |
| `recorder/hello_vr.tscn` | open it, **F6** | Phase 1 headset test (cubes + input readouts) |

Robot Lab and the game run on the monitor. Because VR is on for the whole
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

**Ogre** has one arm, a crane, so it maps differently:

| Input | Ogre |
| --- | --- |
| Head | The huge core turns slowly and only part of the way; the eye (and its light cone) does the rest |
| Right hand | Where the crane's jib tip goes (two-bone IK, knuckle up). The hook hangs below it and sways like a load |
| Right wrist | Turns the hook (yaw only) |
| Right trigger / grip | Closes the grab jaws |
| Left trigger | Winch: pays out cable, lowering the hook |
| Left hand | Nothing (it only has the one arm) |
| A / X, B / Y | Blink shuts the eye's shutter and cuts the beam; flash makes the beam blaze |

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

There is **no Wait**: the player can't just let time pass. Time moves when
they do something that matters: orders, duties, reading a file for the first
time, a conversation, inspecting a device, a round of Night Run, clocking in.
(The F1 dev keys still pass time, for testing.)

Closing the game saves it; opening it resumes at the exact saved moment. The
corkLabs OS clock shows facility time, never the real clock. A new facility
starts at Day 1 05:55, at the first shift's brief (the shift starts at 06:00).

| Piece | File | Job |
| --- | --- | --- |
| `FacilitySim` | `game/sim/facility_sim.gd` | The clock (0.1 s ticks), systems, seeded randomness, save/load. Same save + same actions = same outcome |
| `EventScheduler` | `game/sim/event_scheduler.gd` | Events booked at exact facility times; ties fire in booking order |
| `FacilityLog` | `game/sim/facility_log.gd` | The journal: a timestamped line for everything that happens |
| `Facility` (autoload) | `game/sim/facility.gd` | Session start/save, `spend()` / `act()`, `clock_text()` |
| `ShiftSchedule` | `game/sim/shift_schedule.gd` | Books shift start/end events. The game uses one shift a day (Day, 06:00-14:00); a template for new systems |
| `Campaign` | `game/story/campaign.gd` | The supervisor's three shifts: brief, duties, scripted events, end of shift, the night, endings (see below) |

**Writing a system** (robots, pipes, pods...): any object with `sim_id`,
`sim_tick(sim, dt)`, and optionally `sim_start`, `sim_event`, `sim_save`,
`sim_load`. See `shift_schedule.gd`. Pass it to `Facility.start_session([...])`.

**Dev panel: F1** in any scene with a running facility (the game, once logged on).
**F2** flips pages: overview (clock, booked events, journal), robots (what
each robot is doing, its needs, and its top scores with the reason), full
journal. F5 one tick, F6 +1 min (Shift +1 h), F7 +15 min, F8 wipe the save,
F9 post a random job.

## Robots in the facility

Each robot is a facility system (`RobotAgent`, `game/sim/robot_agent.gd`)
with its own mind. The 3D robot only *shows* it (`RobotView`): when facility
time jumps, the robot rides the rails to where the sim says it is and keeps
performing what it's doing (work clips at a job, idles otherwise).

**Needs**

| Need | Goes down | Goes up | When it runs low |
| --- | --- | --- | --- |
| **Power** | always a little; more moving, most working | on its dock | below its reserve it drops everything to recharge; at 0 it stalls and limps on emergency cells |
| **Software stability** | standing idle (robots think the work keeps *them* running), stalling, being overruled by orders | working, finishing jobs, a reboot | it turns **independent and unpredictable** (below) |

**Software stability** is the heart of a robot's reliability:

| Stability | State | What the robot does |
| --- | --- | --- |
| 60%+ | stable | does as it's told, sensible choices |
| 35%+ | drifting | orders count for less; its choices get whims; it wanders |
| 15%+ | unstable | mostly ignores orders ("No. I have my own work."); errant fixations (loitering at random places) |
| below 15% | critical | **critical errors**: it CRASHES (offline for 10-40 min, then reboots with stability back) or GLITCHES (senseless travel, garbled speech); and it may **sabotage** a device, so there's work it can do |

How it works: *independence* (0 when stable, up to the robot's `independence`
trait) scales down what orders are worth and adds a *whim* to every option:
a random bias that holds for 10 facility minutes, so an unstable robot is
erratic but still follows through. Errant options (fixate, sabotage) get
weight as stability falls. Sabotage looks like an ordinary fault to the
facility (corkHQ may notice "anomalous damage"); the journal's `sabotage`
lines say who did it. Tinker (curious, fidgety) turns independent faster and
is likelier to sabotage than stoic Hauler.

**Deciding: utility scores, like a mixer.** Every couple of facility seconds
a robot scores everything it could do (each reachable job, recharge, stand
by, wander) and does the best. Job scores come from priority × skill ×
distance × power × hunger for work (low stability makes it hungrier). The F1 robots page shows the top scores
and the reason; every change of mind goes in the journal with the runner-up:

```
06:55  Hauler: work #7 Replace fuse (0.60: high priority, precise skill 35%, 12 m away); next best stand by (0.34)
```

**Orders are a strong nudge, not a command.** `agent.give_order(sim, "job", id)`
(or `"recharge"`, `"standby"`, `"cancel"`) adds the robot's `obedience` to
that option. Usually it wins, and the robot says "On it." But below its power
reserve it recharges first, it refuses work it's hopeless at ("No. 'Clear
debris' is heavy work; I'm not built for it.") or can't get to ("I can't get
to Workbench: Freight gate is blocked (jammed)."), and an unstable robot finds
it hard to stand still. It says its answer on camera; it's also journaled.

**Personality** lives in `robots/<id>/<id>_traits.tres` (open it in the
Inspector; every value has a tooltip): rail speed, **width** (which routes
it fits through) and **visual scale**, skills (heavy / precise / general),
power drain and charge, software stability (decay, recovery, order stress,
independence, error resistance, sabotage tendency), obedience, when it refuses, how often
it rethinks, its **voice** (text colour, pitch, wave, speed, how chatty), and
which clips it plays for each kind of work.

| | Hauler | Tinker | Ogre |
| --- | --- | --- | --- |
| Size | 2.4 m wide, drawn 2.6x: huge | 0.7 m wide, normal size | drawn 8x: a 12 m core. **Massive** |
| Skills | heavy 100%, precise 35% | precise 100%, heavy 20% (refuses heavy orders) | heavy 100%, fast (1.6x); precise 10% |
| Rail speed | 1.0 m/s | 1.6 m/s | **never moves** (stationary, crane reach 20 m) |
| Restlessness | low (stoic) | high (curious, fidgety) | very low; hard to rattle |
| Obedience | high | lower | high, but "I decide what I lift" when unstable |
| Voice | low square-wave blips, amber text, speaks rarely | high soft blips, cyan text, chatty | very low, slow saw blips, yellow text, rarely speaks |

**Stationary robots** (traits `stationary` + `reach`): Ogre hangs from the
middle of its hangar's ceiling and never leaves. It scores only jobs within
`reach` meters of its mount (in its own room), "gets there" instantly, charges
on its own mains coupling (a dock on its mount), and turns down anything else
("I can't get to Bay 2: it's out of my reach, and I don't leave the hangar.").
In 3D it slowly turns on the spot to bring its crane round over its work.

## Rooms and routes

**The floor plan** (`game/sim/facility_setup.gd`) is data: rooms, a rail
network, stations, cameras. The simulation plans on it and the 3D world
(`FacilityWorld`, `game/facility_world.gd`) builds itself from it (floors,
walls with doorway openings, rails, signs, cameras), so they always
agree. Rooms are empty space for now.

**The facility is dark.** It was built for robots: no lights, no water, no
washrooms. The only light comes from machines (device status lamps, charging
docks, each robot's status LED: blue ok, amber low power, red blink offline).
Floor stencils and doorway signs are unlit paint. To see, switch a camera to
night vision (below).

| Room | Size | What's in it |
| --- | --- | --- |
| Main hall | 80 x 50 m | a big rail loop and a spine; the three bays |
| Pod bay | 24 x 20 m (north) | the pods |
| Workshop | 14 x 16 m (east) | relay panel, workbench |
| Maintenance | 12 x 12 m (west) | both docks |
| Hangar | 50 x 40 m, 26 m tall (south) | Ogre, hanging from the middle of the ceiling; the loading bay and the deep stacks |

The rails are a **network** (`FacilityLayout`): junctions (nodes) joined by
straight segments. A robot's position is a segment + meters along it; to go
somewhere it plans the quickest route **for its own width**. Segments joining
two rooms are **passages**, and every segment can have caveats:

| Caveat | What it does | Example |
| --- | --- | --- |
| clearance | robots wider than this can't use it | Workshop hatch 1.2 m, pod bay duct 1.0 m: Tinker only |
| blocked | closed to everyone, with a reason | the freight gate jams (a plant fault); `block <route>` in the Terminal |
| speed | slower travel along it | the duct (0.7x), the freight gate (0.6x) |

| Passage | Joins | Caveat |
| --- | --- | --- |
| Pod bay door | hall - pod bay | wide: everyone |
| Pod bay duct | hall - pod bay | narrow: Tinker's shortcut, Hauler goes round by the door |
| Workshop hatch | hall - workshop | narrow: Tinker only |
| Freight gate | hall - workshop | wide but slow, and it **jams** (blocking the route until someone unjams it): Hauler's only way in |
| Dock door | hall - maintenance | wide; the only way to the docks |
| Hangar door | hall - hangar | wide: rail robots can ride in to the loading bay |

**Pads** (`add_pad`) are spots with no rail to them: a tiny segment nobody
can ride (clearance 0), not drawn as rail. Only a stationary robot's reach
gets there. Ogre is mounted on one (`ogre_mount`); the deep stacks are
another, so only Ogre can work them.

If a route closes while a robot is on its way, it re-plans; if there's no way
at all, it gives up the job and says so ("Can't get to Workbench. Freight
gate is blocked (jammed)."). Only jobs a robot can reach are scored. On
camera, blocked passages show a red shutter; each doorway has a sign with its
name and clearance (hazard-striped if narrow). Adding a room: `add_room`,
some `add_node`s, `add_segment`s (including passages to other rooms), and a
camera in `cameras()`: the 3D world follows.

**The work board** (`WorkBoard`, `game/sim/work_board.gd`): jobs with a
title, skill, station, amount of work, priority and progress. A robot claims
a job while it's on it; if it walks away the job goes back on the board with
its progress kept. A finished job fires a `job_done` event, so whatever posted
it can react.

**The plant** (`FacilityPlant`, `game/sim/facility_plant.gd`) is the
machinery the robots keep running. Devices drift or break, post jobs on the
board, and escalate them as they get worse:

| Device | Where | What goes wrong | Job (skill) | Knock-on effect |
| --- | --- | --- | --- | --- |
| Pods 1-4 | pod bay | sync drifts down, faster when hot; at 0 a pod desyncs | Recalibrate (precise), escalates | throughput = average pod sync |
| Filters | each bay | clog slowly | Sweep filters (general) | clogged filters heat the facility |
| Coolant pipes | each bay | leak at random | Clamp coolant leak (heavy, high) | each leak drains coolant; low coolant = hot = pods drift faster |
| Power relay | workshop | fuse blows at random | Replace relay fuse (precise, high) | docks charge at 40% until fixed |
| Bays | main hall | debris falls at random | Clear debris (heavy) | half the time Hauler finds a damaged part: Tinker repairs it at the workbench, then Hauler refits it |
| Freight gate | hall - workshop | jams at random | Unjam freight gate (general, high) | blocks the route until fixed |
| Freight | hangar: loading bay, deep stacks | crates are delivered at random | Stack freight (heavy) | the loading bay can be done by Ogre or a rail robot; only Ogre reaches the deep stacks |

Faults sound an alarm (robots rethink at once); every shift ends with a
report line in the journal (throughput, jobs, faults). Rates and amounts are
the constants at the top of `facility_plant.gd`.

In the 3D world, `FacilityProps` (`game/facility_props.gd`) builds placeholder
props at each station from the same layout: pods glow green → amber → red,
bay lamps flash red on a leak, debris piles appear, the relay and gate lamps
blink when broken, docks light while a robot charges, and a repaired part
waits on the workbench. Every device has a floating label.

`tools/screenshot.gd` can break things before the shot: `--fault pipe_2
--fault relay --spend 600`.

## Robot speech

Robots talk. Their words appear as **coloured text floating above them in
the camera feeds**, typing themselves out with **voice blips**. It's a
framework: the lines and voices are placeholders to replace.

- **When** (`RobotChatter`, `game/speech/robot_chatter.gd`, a facility
  system): robots report what happens to them (starting and finishing jobs,
  recharging, low power, stalling, moods, wandering, blocked routes, answers
  to orders); an idle robot sometimes mutters; two robots close together in
  the same room strike up a **conversation** (one speaks, the other answers a
  few seconds later), sometimes passing on a job the other is better at;
  alarms and closed routes get a comment. Urgent things are always said; the
  rest depends on each robot's cooldown and chattiness. Everything said goes
  in the journal (`speech`), and talk has its own random numbers, so it never
  changes what else happens.
- **What** (`game/speech/barks.txt`, a plain text file): one line per bark,
  `trigger | robot | condition | text`, with conditions (`low_power`,
  `stable`, `drifting`, `unstable`, `critical`, `working`...) and
  placeholders (`{station}`, `{job}`, `{peer}`, `{power}`...). Lines whose
  condition holds are picked more often, so a tired robot mostly sounds tired.
  The robot field can leave robots out: `any !ogre` is every robot but Ogre
  (for lines about riding the rails, which Ogre never does).
  Edit it freely; the format is at the top of `bark_library.gd`.
- **How it shows** (`SpeechDirector`, `os/speech_director.gd`): one line per
  robot at a time (a newer one replaces it), typed at the robot's
  `voice_speed`, held, faded. A feed draws it over the robot if its camera is
  in the same room and can see it. You only **hear** a robot while it's on an
  open camera.
- **Voice** (`RobotVoice`, `game/speech/robot_voice.gd`): short blips built
  from the robot's traits (pitch, variation, wave), one per letter or two.
  `use_samples([...])` swaps in recorded sounds later. Settings has Voices
  on/off and volume.

## Camera audio

You hear the facility **through the security cameras**: the camera is the
microphone. A framework for sound design; the sounds themselves are
placeholders.

- **Mixer** (`default_bus_layout.tres`, the **Audio** tab at the bottom of the
  Godot editor; names in `FeedAudio`, `game/audio/feed_audio.gd`):

  | Bus | Sends to | What goes there |
  | --- | --- | --- |
  | `Feed` | Master | everything heard through a camera. **Mute** in Cameras (button or M), volume in Settings |
  | `Voices` | Feed | robot speech blips |
  | `World` | Feed | positional sound in the facility: motors, machines, auditions |
  | `UI` | Master | the OS itself (corkHQ chime) |

  Add inserts (EQ, compressor, a band-pass "CCTV mic", reverb) to a bus in the
  Audio tab and everything on it gets them, like a channel strip.
- **Which camera you hear**: the open one in single view; in the grid, the
  one under the mouse (none otherwise). Its feed says `AUDIO` (or
  `AUDIO MUTED`) bottom-left. Only one camera listens at a time.
- **Sounds in the world** (`FacilitySound`, `game/audio/facility_sound.gd`):
  a 3D player on the World bus with the facility's attenuation (inverse
  distance: `unit_size` = metres at full volume, `max_distance` = silent
  beyond), a high-frequency roll-off with distance, and **room awareness**:
  from another room it's `through_wall_db` (-30 dB) quieter and low-passed
  to 500 Hz, eased in over a quarter second. Make one a child of whatever
  makes the noise. Example: every robot has a **motor hum** (`RobotView.motor`)
  that gets louder and higher with speed; bigger robots hum lower and carry further.
- **Sounds by name** (`SoundBank`): files in `game/sounds/` first, then the
  generated placeholders (`SoundSynth`: tone, noise, hum, click). A recorded
  `hum.wav` there replaces the generated hum by name.
- **Auditioning** (Terminal): `sound` lists sounds and the camera you're
  hearing; `sound play <name> 15` plays it 15 m in front of that camera;
  `sound play <name> tinker` on a robot (it rides along); `sound loop <name> hall`
  loops it in the middle of a room; `sound stop`; `sound mute` / `unmute`.
  Switch cameras while one loops to hear distance, panning and walls change.

## Folder map

| Folder | Contents |
| --- | --- |
| `recorder/` | VR recorder scene, `PerformanceFrame` (one moment), `PerformanceTake` (a recording) |
| `pipeline/` | Cleanup (`take_cleanup.gd`, `cleanup_recipe.gd`), baking (`baker.gd`), comping (`take_comp.gd`), springs, filters |
| `robots/` | One folder per robot: scene + rig script + profile. `robot_rig.gd` is the shared base |
| `takes/` | Your recordings (keep these!). `takes/demo/` = procedural demo takes, delete any time |
| `animations/` | Baked clips + one `AnimationLibrary` per robot (regenerated by baking) |
| `game/` | `RobotActor` (plays clips via AnimationTree), `RobotView` (3D robot rides the rails after its sim self, with pendulum sway), `FacilityWorld` (the 3D facility, built from the layout), props, cameras, Robot Lab |
| `game/sim/` | The facility simulation: clock, scheduler, journal, rooms + rail network, work board, plant, robot agents and traits |
| `game/audio/` | Camera audio: buses (`FeedAudio`), `FacilitySound` (3D emitters), `SoundBank`, `SoundSynth` (placeholder sounds) |
| `game/sounds/` | Sound files to audition by name (drop .wav/.ogg/.mp3 here) |
| `game/speech/` | Robot speech: `barks.txt` (the lines), `RobotChatter` (when), `BarkLibrary`, `RobotVoice` |
| `game/corporate/` | Corporate: `CorkHQ`, `Requisitions`, `SoftwareLibrary`, and their data files (`hq_lines.txt`, `catalog.txt`, `packages.txt`) |
| `game/story/` | The story: `Campaign` (shifts), `Knowledge` (what you've found), `Oversight` (standing, suspicion, audits, dismissal), `VirtualFS` + `fs/` (the OS's files), `Dialogue` + `dialogue/` (conversations), `SupervisorArchive` (across runs), and the data files. See [docs/STORY.md](docs/STORY.md) (spoilers) |
| `os/` | The corkLabs OS: desktop, windows, theme, and its apps (`os/apps/`) |
| `addons/corklabs_pipeline/` | The editor Takes panel |
| `tools/` | Command-line tools (bake all, demo takes, screenshots, test runner) |
| `tests/` | Automated tests, no headset needed |

## The corkLabs OS (the game screen)

`os/desktop.tscn` is the main scene: **F5** boots the game straight into the
corkLabs OS, the supervisor's desktop, where the game is played. (Like the
other flat scenes it restarts itself without VR. The VR recorder is now
`recorder/recorder.tscn` + **F6**.)

- **Boot screen**: a few lines of start-up text; any key or click skips it
  (can be switched off in Settings).
- **Log on** opens the real facility (`user://facility_save.json`) exactly
  where you left it, and reopens the windows you had open, where they were.
  The greeting uses your Windows user name (the only thing it reads from the PC).
  The login screen also shows your **personnel file** (every run so far).
  **Shut down** quits.
- **Shift screens** cover the desktop between shifts: the **brief** (Clock
  in), **end of shift** (Clock out: the night passes), **dismissal** (retry
  the shift, or start over), and the **ending**. See "Shifts and the story".
- **Windows**: open apps from the desktop icons (double-click), the
  **corkLabs** start menu, or a right-click on the desktop. Drag the title
  bar to move; drag to the left/right screen edge to snap to half the screen,
  to the top to maximise; double-click the title or use □ to maximise; resize
  from the corner; minimise to the taskbar; close. Keys go to the focused
  window (e.g. arrow keys pan the camera).
- **Desktop right-click**: show desktop (minimise all), cascade, close all,
  Settings.
- **Taskbar**: open windows, a blinking **ALARM** light while anything is
  broken (click: Plant), throughput, and the **facility clock** with the
  shift (never the real clock). No Wait button, on purpose.
- **Discoveries** (a secret, a new program) pop up as a toast. Some apps
  aren't on the desktop until you find them (Night Run); the start menu shows
  them as "???".
- **Notifications**: alarms and shift reports pop up bottom right (each kind
  can be turned off in Settings) and are all kept in the
  **notification centre**: click the clock (a dot means there's something new).
- **F1** dev panel works here too.

| App | What it shows | What you can do |
| --- | --- | --- |
| **Cameras** | Seven CCTV cameras across the rooms (two in the hangar), one at a time or all in a grid; robots' speech floats over them. **Observation only** | Drag to pan/tilt, scroll to zoom, double-click to reset; arrows, + / -, Home; 1-9 camera, G grid, **N night vision**, F filter, M mute. You hear the facility through the open camera (grid: the one under the mouse). Feeds run at a locked 30 fps. Cameras can auto-track a robot (none do right now). All free: looking costs no time |
| **Duties** | Corporate's checklist for this shift | Do a duty (its minutes); undone ones cost standing at 14:00. Some tick themselves off (read the Code of Conduct) |
| **Units** | Each robot: what it's doing, power, software stability (and how independent it is), standing order, what it's weighing up and why | Order: recharge, stand by, cancel (2 min); **Diagnose** (10 min, steadies it a little); **Talk** (once you know you can: opens the unit link in the Terminal); **remote reboot** (needs the remote-reboot package) |
| **Requisitions** | The catalogue (resources, parts, new robot models), your budget, your orders and their status, stock | Order items (2 min); corporate approves the big ones, corkHQ reports every step |
| **Work Orders** | The job board (open, or all with finished) | Order a robot onto a job; raise/lower priority (2 min) |
| **Plant** | Throughput, coolant, heat, dock power, every device's state and job | Pick a device: **Inspect** (10 min: wear rate, when it needs work, who's on it), **Request maintenance** (post the job early, 2 min), **Use spare part** from Requisitions stock (shrinks the repair, 2 min) |
| **Files** | The OS file system (the same files as the Terminal) | Read files (the first read costs time), decrypt, run programs; hidden files once you know they exist (`ls -a`) |
| **Facility Log** | The whole journal with filters (alarms, robots, work, plant, you) | |
| **Terminal** | The command line you **learn**: `help` lists only the commands you know (a new supervisor knows `ls`, `cd`, `cat`, `pwd`, `status`, `clear`); files, corkHQ, units and a game teach the rest, and typing any real command teaches it | Everything the apps do, plus the file system (`ls -a -l`, `cd`, `cat`, `decrypt`, `run`), `talk <unit>` (numbered replies, 0 closes), `duties`/`duty <id>`, `whoami`, and the maintenance account (`su maint`: `auditctl`, `hqctl`, `unitctl`, `pkgctl`, `podctl`). Up/down for history, Esc cancels |
| **Night Run** | Not on the desktop until found (`/opt/games`). A former supervisor's arcade game: a cart on a rail in the dark | Left/right, Space, Esc. Each run costs 10 facility minutes (and is logged). It has secrets |
| **Settings** | Interface size, fullscreen, boot screen, reopen windows, which pop-ups show, camera sound (mute, feed volume), robot voices + volume, forget window layout | |

Robots answer orders out loud, on camera; the apps just say the order was sent.

Every supervisor action goes through `Supervisor` (`game/supervisor.gd`),
which journals it and spends the time (an order or priority change: 2 min;
reading, talking, duties, inspecting, playing: see docs/STORY.md). Opening
apps and looking through cameras is free.

The **corkHQ panel** has one button: **Reply**, a conversation with Liaison
Pell inside the panel (it costs time; what you say is noted).

OS preferences and the window layout are saved in `user://os_settings.json`
(`OSSettings`), separate from the facility save: they're the player's
desk, not the facility.

How it's built: the 3D facility (`game/facility_world.tscn`) runs once,
hidden, inside a SubViewport; each camera feed (`CCTVFeed`,
`os/cctv_feed.gd`) renders it through its own viewport and camera, copying a
`SecurityCamera` (`game/security_camera.gd`: a pan/tilt/zoom head with
limits and a motor that eases). Night vision swaps the feed camera's
Environment for an infrared one (flat light, black distance fog) and flips the
feed shader (`os/cctv_feed.gdshader`) to green phosphor. Each feed renders
once per 1/30 s (`CCTVFeed.FEED_FPS`). Apps are `OSApp` scripts in `os/apps/` that
build their UI in code, `refresh()` from the running facility, can take keys
(`key_input`) and remember their view (`save_state`/`load_state`); the look is
one `OSTheme` (`os/os_theme.gd`). Adding an app: copy one in `os/apps/`, give
it an id/title/icon in `_init()`, and add it to `APPS` in `os/desktop.gd`.

`tools/screenshot.gd` can drive it: `--call log_on --call open_app:plant`.

## Shifts and the story

The game is **three shifts** (Day 1-3, 06:00-14:00) in one continuous
timeline, run by `Campaign` (`game/story/campaign.gd`). Each shift has a
brief, **duties** (corporate's checklist), **scripted events** (corkHQ
messages, robot lines, faults, audits, clips to perform) and ends at 14:00
with a review. Clocking out runs the night (the facility carries on without
you) up to the next brief. After shift 3: an ending, picked from what you did.

`Oversight` (`game/story/oversight.gd`) is how corporate judges you:
**standing** (0-100; reviews, duties, crashes; 0 = dismissed for
performance), **suspicion** (policy violations; hourly audits; two catches =
dismissed for misconduct) and **catastrophes** (coolant empty 30 min,
throughput under 30% for an hour). Dismissal offers **retry the shift** (the
save is checkpointed at every brief: `facility_save_checkpoint.json`) or
**start over**.

`Knowledge` (`game/story/knowledge.gd`) is what this supervisor has found:
commands, files read, secrets, story flags. Conditions everywhere (files,
events, duties, dialogue, endings) check it.

The OS has a **file system** (`game/story/fs/`, one text file per file, with
`#!` headers for hidden, encrypted, restricted, appearing, disappearing
files), former supervisors' home folders, corporate memos, logs, a game.
Units can be **talked to** (`game/story/dialogue/*.txt`: a small script
format with choices, conditions and effects).

Everything's data: rewrite any line without touching code. The full map of
secrets, chains and endings, and the list of clips to perform in VR, is in
**[docs/STORY.md](docs/STORY.md)** (spoilers).

## Corporate: corkHQ, requisitions, software

Corporate lives in three facility systems (`game/corporate/`) and one
window the player can't get rid of.

**corkHQ** (`CorkHQ` + `CorkHQPanel`, `os/corkhq_panel.gd`): pinned to the
top-right corner of the OS, above every window. No close, minimise, move or
resize; every new message chimes (at a fixed volume, whatever the settings),
flashes and shakes. The header judges you: rating, funds, clearance. It
posts: a welcome (including where the software server is), a directive each
shift, a **graded review** at the end of each shift (A-F from throughput vs
the 85% target), nagging when throughput is low or units sit idle, reactions
to crashes and "anomalous damage", and feedback from requisitions and
software (confirmations, approvals, denials, install codes). Its lines are
in `game/corporate/hq_lines.txt`.

**Requisitions** (`Requisitions` + the Requisitions app): a budget that
corporate tops up after every review (more for a better grade), and a
catalogue in `game/corporate/catalog.txt` (resources, replacement parts, new
robot models: price, delivery hours, whether corporate must approve it, and
what happens on delivery). Orders go pending → approved/denied (refunded) →
in transit → delivered. Placeholders for now: delivered parts go into stock
and robot units arrive crated; the coolant canister is wired (tops up the
reservoir).

**Software packages** (`SoftwareLibrary`, `game/corporate/packages.txt`):
unlockables downloaded from the Cork package server **through the
Terminal**. The commands aren't in `help`: IT Services' welcome in corkHQ
gives the server address, and the server explains the rest.

```
connect cork://pkg.corklabs.int     open a session (then the server lists its commands)
corkpkg list                        packages, their clearance level, what's LOCKED for you
corkpkg info <package>
corkpkg request <package>           IT reviews it; the answer (and an install code) arrives in corkHQ
corkpkg install <package> <code>    downloads and installs (takes facility time)
corkpkg installed
```

Corporate only approves packages up to your **clearance** (1-3), which rises
with A/B reviews and falls with an F. Three packages already do something:
`remote-reboot` (the Units app's Reboot button), `route-control` (the
Terminal's `block` / `unblock`), `firmware-stabilizer` (robots' software
drifts half as fast). The rest (peer-sync, pathfinder-pro,
predictive-maintenance, self-service, diag-suite, night-watch, overclock)
are placeholders for robot behaviours and supervisor tools to come. Check
for one in code with `Supervisor.has_software("id")`.

## Using robots in the game

```
RobotView (on the rail network)      game/robot_view.gd: rides routes, faces travel, catches up after time jumps, performs story clips
└── Swing                            pendulum pivot (sway when it speeds up, brakes or turns)
    └── RobotActor                   robot_id = "hauler", scaled by traits.visual_scale
```

`RobotActor` loads the robot and its clip library, loops `idle*` clips
(crossfading to a random different idle each time), and
`play_action("act_weld")` plays any clip over the idle with fades.
`FacilityWorld` makes one `RobotView` per robot in `FacilitySetup.START_STATIONS`.

## Adding a robot

1. Copy `robots/tinker/` (core-bot, telescoping arms), `robots/hauler/`
   (hanging body, neck, two-segment arms) or `robots/ogre/` (huge core, one
   crane arm with a hanging hook, eye spotlight + light cone) to `robots/<newname>/`, and rename
   the three files to `<newname>.tscn`, `<newname>_rig.gd`, `<newname>_profile.tres`.
2. Fix the paths inside the `.tscn` (script + profile) and the profile's
   `display_name`.
3. Change the shapes. Node names the rig script looks up must stay (or edit
   `_bind()` in the rig script). Arm segment lengths are read from the scene.
4. It shows up automatically in the recorder (Left X), Robot Lab and the
   Takes panel.
5. To put it in the facility: a `robots/<newname>/<newname>_traits.tres`
   (copy one; set width, scale, skills, voice; `stationary` + `reach` for a
   robot that never moves, like Ogre) and a start station in
   `FacilitySetup.START_STATIONS` (that's all `systems()` and the 3D world need).
   Give it lines in `barks.txt` (or it uses the `any` ones).

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
