# corkLabs: design

The *why* behind the project: premise, pillars, and the decisions made so
far (with dates), so nobody has to rediscover them. How-to lives in the
[README](../README.md); status and next steps in [ROADMAP.md](ROADMAP.md).

## Premise

- A state-of-the-art **organic computing compound**: thousands of humans are
  kept in a simulation ("the matrix") and used for processing power.
- The compound is maintained by **robots transported on rails** (think
  Wheatley from Portal). They don't know what a human is. To them, the tasks
  they do keep *themselves* running, not anyone else.
- Each robot is **its own AI** with a distinct purpose and silhouette: some
  built for brute labour, some for precise procedures. Most have arms; all
  have heads/eyes.
- **The player** is a newly appointed human **supervisor** for this team. They
  work for a government organisation that exists *inside* the matrix, knows
  it's the matrix, and hides that from the population (conspiracy-theory
  style). The player's in-matrix life is their real life, and their
  outside-life is the agent. They supervise the robots **from their desktop**.

## Pillars

1. **The robots are the core.** They are dynamic characters that respond to
   the supervisor's directions, to each other, and to changes in the
   environment. Their reactions to the supervisor's choices shape the events
   of the game.
2. **Performed, not keyframed.** Robot motion is performed in VR (head,
   hands, controller inputs) and baked into animations, so every robot has
   a human performance behind it, filtered through a machine.
3. **The desktop is the world.** The game is a fake desktop OS (the "corkLabs
   OS"): camera feeds, apps, messages. It touches the player's real PC only
   lightly.

## Decisions log

| Date | Decision | Why |
| --- | --- | --- |
| 2026-09-28 | Robots hang from rails and have no legs, hips or spine | VR tracks head and hands only; nothing is guessed from missing data |
| 2026-09-28 | Takes (raw VR recordings) are the source of truth; animations are rebaked from them | Models, rigs and personalities can change without re-recording |
| 2026-09-28 | Custom recorder inside Godot, Quest 3 over the Meta Link cable | Same engine and coordinates as the game; Link is the most direct wired path (Virtual Desktop was unreliable) |
| 2026-09-28 | Rigid `Node3D` robot rigs with simple IK baked offline | No skinning or weight painting; move to `Skeleton3D` + Godot 4.6 IK only when reactive IK is needed |
| 2026-09-29 | Nothing on a robot may read as a leg: elbows point up, hands map relative to a rest pose | Long arms hanging down looked like legs in early renders |
| 2026-09-29 | Clip naming: `idle_*` (loops), `act_*` (actions), `cs_*` (cutscenes) under `takes/<robot>/` and `animations/<robot>/` | Timestamp names were unreadable; the prefix tells the game how to use a clip |
| 2026-09-29 | Player's screen is a **fake desktop OS** | Fits the "supervisor at their desk" premise |
| 2026-09-29 | Real-PC integration is **light touch** (clock/date, username, and the like; no reading their files) | Personal but safe |
| 2026-09-29 | **Facility time only moves when the player acts** (Disco Elysium style): each dialogue line, choice or interaction spends facility time | Precise control over what happens when; the player can log on/off freely |
| 2026-09-29 | Closing the game freezes facility time; reopening resumes at the saved moment. The corkLabs OS clock shows facility time, never the real clock | Replaced an earlier "slow offline time" idea as too complex |
| 2026-09-29 | First playable target: **one shift, start to end** | Proves the whole loop small |
| 2026-09-29 | Before gameplay: build developer tools, readability, and robot-behaviour scaffolding | Robots are the core; they need a solid, debuggable foundation |
| 2026-09-29 | Robots decide with **utility scores** (every option scored, best wins; personality = weights) | Readable: scores + reasons show on the dev panel and in the journal; tuned like faders; new options slot in without rewiring |
| 2026-09-29 | Supervisor orders are a **strong nudge**, not a command: they add `obedience` to that option, and robots can push back | Refusals ("recharging first", "not built for it", "can't stand still") become story moments |
| 2026-09-29 | Robot needs: **Power** and **Purpose** (idleness feels like dying to them). Wear and trust left for later | Power gives logistics; Purpose fits "the work keeps *them* running" and gives robots an inner life |
| 2026-09-29 | The sim owns robot state; the 3D robot follows it (`RobotView`) and keeps performing its current activity in real time | Time only moves on player actions, so the world must be able to "catch up" smoothly after a jump |
| 2026-09-29 | Behaviour personality is a separate resource (`<id>_traits.tres`) from the motion profile | Mind and motion tune independently; motion changes need a rebake, mind changes don't |
| 2026-09-29 | The facility's machinery is one `FacilityPlant` system: pods (sync), filters, coolant pipes, power relay, bays. Devices drift or fault, post and escalate jobs | One place to read how the facility behaves; devices are data, so more can be added cheaply |
| 2026-09-29 | Problems **chain**: leaks drain coolant, heat speeds pod drift, a blown fuse slows robot charging | Neglect should snowball, so the supervisor's choices (what to prioritise, when to overrule) matter |
| 2026-09-29 | A salvage chain hands work between robots (Hauler finds a part, Tinker repairs, Hauler refits) | Robots visibly depend on each other (pillar 1) without needing shared rails |
| 2026-09-29 | Baseline tuning: the two robots keep up (~86% throughput, ~27 jobs a shift) | Normal running should be calm; incidents and story events will push it over |
| 2026-09-29 | The corkLabs OS is built in code (`OSApp` scripts + one `OSTheme`), not as .tscn UIs | Easy to read, diff and restyle in one place; apps are small and uniform |
| 2026-09-29 | The 3D facility runs once, hidden, in a SubViewport; camera windows render it through their own viewports | One simulation view, any number of feeds, and the demo reuses the same world scene |
| 2026-09-29 | Every supervisor action goes through `Supervisor` (journals it as "you", spends the time) | One place to tune what costs time; Messages can show your side of the conversation |
| 2026-09-29 | For now opening apps and switching cameras is free; orders and priority changes cost 2 min; Wait passes 5 min to 4 h | Placeholder until the user decides which OS actions should cost time (see ROADMAP) |
| 2026-09-29 | Wait passes facility time a minute per frame and stops on an alarm or shift report | No freeze on long waits, the player watches it happen, and "wait until something happens" becomes a real move. Still player-initiated, so time only moves on player actions |
| 2026-09-29 | The OS greets the player by their Windows user name (the only real-PC read) | Light-touch personal touch, per the real-PC decision |
| 2026-09-30 | The game stays **inside the fake corkLabs OS** (not native windows on the real desktop), and the game boots straight into it | User's choice: the OS is the world; keeps framing, streaming and tutorials under control |
| 2026-09-30 | The Cameras window is **observation only**: camera control (pan/tilt/zoom, switching, grid, auto-track) and nothing that changes the facility. Controls live in the other apps | User's choice: observing and acting are separate windows the player opens and closes freely |
| 2026-09-30 | Camera control is **free** (no facility time) | User's choice: looking is not acting |
| 2026-09-30 | Pan/tilt/zoom lives on the `SecurityCamera` itself (a motorised head with limits), so every feed of a camera shows the same view | Like real CCTV; the demo and all feeds agree |
| 2026-09-30 | OS preferences and window layout are saved separately from the facility (`os_settings.json`) | They're the player's desk, not game state; wiping a facility doesn't reset your desk |
| 2026-09-30 | A Terminal app mirrors every supervisor action as typed commands | Fits the "supervisor terminal" fiction; handy for power users and testing |
| 2026-09-30 | Priority is **frameworks over finished features**: build the structure each idea needs, with placeholder content | User's direction: develop the ideas for future implementation |
| 2026-09-30 | **Rooms**: a very large main hall (80 x 50 m) with smaller rooms attached (pod bay, workshop, maintenance). Empty for now | User's direction; scale makes the robots feel like part of a huge machine |
| 2026-09-30 | Rails are a **network across rooms**; robots plan routes for their own width. Passages have **caveats**: clearance (too narrow for Hauler), blocked (the freight gate jams), speed | User's direction: travel needs a valid path, and routes have catches |
| 2026-09-30 | The floor plan is **data** (`FacilitySetup.layout()`); the 3D world builds itself from it | Sim and camera view can never disagree; adding a room is a few lines |
| 2026-09-30 | A robot whose route closes re-plans; with no way at all it gives up and says why | Makes blocked routes visible and legible, not silent failures |
| 2026-09-30 | **Hauler much larger** (2.6x drawn, 2.4 m wide) | User's direction; also what makes narrow routes matter |
| 2026-09-30 | Messages app, robot-message pop-ups and Handbook **removed**. Facility Log kept (debug journal) | User's direction: robots speak on camera instead; the Log is how we debug decisions |
| 2026-09-30 | Robots **speak as coloured floating text over them in CCTV feeds**, with voice blips; lines vary with their condition (power, purpose, mood); they talk to each other | User's direction |
| 2026-09-30 | Speech is decided in the simulation (`RobotChatter`, own random numbers, saved) and shown by the OS (`SpeechDirector`) | Deterministic and journaled like everything else, without changing what else happens |
| 2026-09-30 | Lines live in a plain text file (`barks.txt`: trigger / robot / condition / text) | Writable without code; conditions weight the choice so the robot's state shows |
| 2026-09-30 | Voices are generated blips per robot (pitch, wave, speed in its traits); recorded samples can replace them | Placeholder sound now, real sound design later without code changes |
| 2026-09-30 | You only hear a robot while it's on an open camera | The cameras are the player's senses |
| 2026-09-30 | **Camera audio**: the facility is heard through one camera at a time (single view: the open one; grid: the one under the mouse); that feed's viewport is the 3D audio listener | The camera is the microphone; one listener keeps the mix readable and makes room rules possible |
| 2026-09-30 | Buses: `Feed` (Voices + World under it) and `UI`, all to Master; the Cameras mute silences Feed | A mixer the sound designer can put inserts on in the editor; mute covers everything from the cameras and nothing from the OS |
| 2026-09-30 | Sounds in another room than the listening camera are -30 dB and low-passed (per-emitter, eased) | Matches speech's same-room rule without making other rooms dead silent |
| 2026-09-30 | Placeholder sounds are generated (`SoundSynth`); files in `game/sounds/` override them by name; the Terminal's `sound` command auditions them in place | Sound design can start by dropping in files, no code |
| 2026-09-30 | Robot voices stay non-positional for now (on the Voices bus) | They already work well; making them 3D is a later call |
| 2026-09-30 | The flat demo scene is retired (the OS is the game) | One place to see the facility; less to keep in step |
| 2026-09-30 | "Purpose" becomes **software stability**: low stability makes a robot independent, unpredictable and unreliable (orders count for less, errant behaviour rises), then critical errors (crash/glitch), then sabotage | User's direction: instability is the robots' inner life and the facility's risk |
| 2026-09-30 | Unpredictability is a **whim** per option that lasts 10 facility minutes, not per-think noise | Erratic but legible: an unstable robot surprises you, then follows through |
| 2026-09-30 | An unstable robot sabotages devices **it can fix**, to make work for itself | Fits the premise (the work keeps *them* running); a self-feeding loop the supervisor must break |
| 2026-09-30 | Being overruled by orders costs a little stability (`order_stress`) | Micromanaging has a price; trust vs control becomes a choice |
| 2026-09-30 | The Hauler tracker camera is removed (tracking stays in the framework) | User's direction |
| 2026-09-30 | **Corporate** = three systems (corkHQ messages and reviews, requisitions + budget, software packages) plus an unclosable, unmutable **corkHQ panel** top-right | User's direction: corporate is invasive and judges you |
| 2026-09-30 | The budget comes from shift reviews (grade A-F vs an 85% throughput target) | Performance drives resources; resources drive performance |
| 2026-09-30 | Software packages are learned and installed through the **Terminal** (connect, corkpkg), approved by corporate by **clearance**, with install codes delivered via corkHQ | User's direction: the player learns the commands; corporate gates progress |
| 2026-09-30 | Catalogue, packages and corkHQ lines are plain text data files | Content can grow without code |
| 2026-09-30 | **The facility is dark**: no lights, no human amenities (water, washrooms, anything). Only machines give off light (status lamps, docks, robot LEDs); floor stencils and signs are unlit paint | User's direction: built for robots, not people; they work in the dark, literally and metaphorically |
| 2026-09-30 | Cameras get **night vision** (N / checkbox): a per-camera IR Environment (flat light, black fog for the illuminator's reach) + green phosphor shader. It's only looking: free, per Cameras window, remembered | The player needs to see; the dark stays the default, so looking is a deliberate act |
| 2026-09-30 | Robots carry a **status LED** (blue ok, amber low power, red blink offline) | How you find a robot in the dark without night vision; makes its state visible at a glance |
| 2026-09-30 | Camera feeds are **locked to 30 fps** (render once per tick; grain and roll step on the same clock) | User's direction: reads as CCTV, and saves rendering with several feeds open |
| 2026-09-30 | New robot **Ogre**: a massive (8x, 12 m) spherical core with ONE arm, a knuckle-boom crane; dark muted greys, yellow core lights; its big eye throws a visible yellow light cone | User's design |
| 2026-09-30 | Ogre is **stationary**: bolted to the centre of its hangar's ceiling, never changes rooms. Works anything within its crane's reach (20 m); charges from its own mains coupling | User's design. Built as a general `stationary` + `reach` trait so any future fixed robot works the same way |
| 2026-09-30 | Ogre's hangar is a new room (50 x 40 m, 26 m tall) south of the main hall with a wide door; freight arrives there (heavy work). The loading bay is shared with rail robots, the deep stacks are Ogre-only (a railless "pad") | Gives the crane something to do, and a place where Ogre and the rail robots meet. Placeholder content for the user to redesign |
| 2026-09-30 | The light cone is a fake volumetric mesh (additive shader, soft where it meets the floor) plus a real spotlight | Works in every renderer and costs little; no fog set-up needed |
| 2026-09-30 | Crane mapping: right hand = jib tip (knuckle up), left trigger = winch, right trigger = grab; the hook hangs and sways on a spring | One arm for a one-armed robot; the knuckle points up so the crane never reads as a leg |
| 2026-09-30 | **Wait is removed** (taskbar, Terminal, Supervisor). Supersedes the 2026-09-29 Wait decisions | User's direction: time ONLY passes when the player engages with key mechanics (duties, reading, dialogue, interactions, discoveries), so they're pushed to act, and to act out |
| 2026-09-30 | The game is **one continuous timeline of three shifts** (Day 1-3, 06:00-14:00), one shift a day; the night between is simulated with no supervisor | User's direction: shifts separate the big segments, pace and gate mechanics; runs can go very differently depending on what was found |
| 2026-09-30 | Between shifts: a **brief** (clock in), an **end-of-shift** screen (clock out: the night passes in chunks on screen) | Clear chapter breaks; the night gives the facility room to change while you're away (overnight summary in the next brief) |
| 2026-09-30 | **Dismissal**: performance (standing 0), misconduct (two audit catches), catastrophe (coolant dry 30 min / throughput under 30% for an hour). Retry the shift from a **checkpoint saved at its brief**, or start over | User's direction: you can get fired for poor performance, catastrophe or getting caught; failing sends you back to the start of the shift or a new save |
| 2026-09-30 | Corporate's judgement is two numbers: **standing** (visible on the corkHQ panel) and **suspicion** (hidden; the maintenance account's `auditctl` shows the trail) | The good-supervisor path and the rascal path pull on different meters; suspicion being hidden keeps the dread |
| 2026-09-30 | **Duties** (corporate's checklist per shift) are the good-supervisor path and a steady way to spend a shift's time; undone duties cost standing | Sucking up to corporate has to be a real, playable choice, not just "don't snoop" |
| 2026-09-30 | The **Terminal is learned**: `help` lists only known commands; typing any real command works and teaches it; files, units and corkHQ teach the rest | User's direction: the terminal starts as an unknown and help was getting cluttered. Typing works regardless, so what the PLAYER remembers carries across runs |
| 2026-09-30 | The OS has a **file system** of plain text files (`game/story/fs/`) with former supervisors' homes; hidden, encrypted, restricted, appearing and disappearing files by header | User's direction: the facility and OS are old and have history; evidence of previous supervisors. Content can grow without code |
| 2026-09-30 | Five former supervisors (Hollis, Marrow, Vance, Kim, Okafor); every one was "transferred" into a pod | Makes "you're not the first" the spine of the mystery, and "transferred" a phrase that curdles |
| 2026-09-30 | **Night Run**, Marrow's arcade game, hidden in `/opt/games`: passes time (10 min a run), is against the rules, holds two secrets (the top score is a password; the wrong way holds a message) | User's direction: minigames as time passes and a place to hide secrets (Midnight Motorist) |
| 2026-09-30 | A **maintenance account** (`su maint`) unlocks rule-breaking tools: audit trail, muting corkHQ, forcing packages, resetting units, the pods | The rascal path's "features recovered": later shifts play very differently with it |
| 2026-09-30 | Talking to units is a **conversation script** (plain text, choices, conditions, effects); it costs time, steadies the unit, and is a small violation | Talking to the robots becomes a real mechanic with a trade-off (trust vs compliance) |
| 2026-09-30 | The corkHQ panel gets one button, **Reply** (a conversation with Liaison Pell) | The liaison gets a face you can push against, without making the panel any less inescapable |
| 2026-09-30 | A **personnel file** across runs (secrets, endings, dismissals), shown at login and on the ending screen; it never changes a run's rules | Encourages replays; carrying knowledge stays the player's job |
| 2026-09-30 | Story beats can ask a unit to **perform a named clip**; nothing happens until it's recorded | Robot story moments get acted in VR later, without blocking the writing |
| 2026-09-30 | Plant actions (inspect, request maintenance, spare parts from stock) and unit diagnostics | More to do inside the OS's systems; makes Requisitions matter |
| 2026-09-30 | **Pacing x3-6**: dialogue line 3 min, choice 5, interaction 15, task 45; reading x3; inspect/diagnose 30; Night Run 30 a run | User: one shift showed nearly the whole game. A shift should hold a couple of dozen real actions |
| 2026-09-30 | **Longer chains, not shift locks**: former staff homes are locked by account (`#! access:`); Okafor's account needs his password, which Tinker only gives after trust 3 (one conversation every 2 h); Marrow, Hollis and the pods need maint | User's choice (costs + knowledge chains). A new player can't know the way; a returning one still has to earn it |
| 2026-09-30 | **The facility fights back**: doors stick (block routes), cameras die, the uplink can fail; fault rates up; per-shift pressure (orientation 0.65, audit day 1.15, nights 0.4) | User: the player should be sucked back into work by the facility's ineptitude |
| 2026-09-30 | **Repairs use parts**; no part = the job stops halfway. Small starting stock, express shipping | User: Requisitions must matter |
| 2026-09-30 | **Unit wear**: slows units; past 50% they seize and need a manual reboot by another unit (or free themselves after 2 h); services use servo bundles | User: bots need more to do and must demand attention (also: mechanical failures needing a manual reboot by Tinker) |
| 2026-09-30 | **Units ask for things** (requests with answers and a deadline); ignoring them hurts their stability | User: robots ask for things |
| 2026-09-30 | **Directives**: corporate's timed demands; **Pell escalates** per kind of violation (warning, explain yourself, Compliance + targeted audit) | User: Escalating Pell + demands that interrupt |
| 2026-09-30 | **The uplink**: while down, nothing is recorded and no audits run; Hauler (trust 2) can be talked into an "accident"; corporate wants it back within the hour; repeat outages are suspicious | User's pick for dodging audits (uplink blackout) |
| 2026-09-30 | Shift 1 is **orientation**: tutorial duties that tick off as you use each system, and scripted incidents that introduce them one at a time | User: day 1 as a tutorial on the OS, the bots, surface files and terminal |
| 2026-09-30 | **Endings scrapped for now**, archived in docs/archive/endings.txt; the run ends with "the end of this build" | User's direction |
| 2026-09-30 | Nights: units in standby (stability drifts 15%, wear 30%, no seizing); corkHQ doesn't post to an empty desk | Unattended nights shouldn't wreck a decently run facility; what you leave undone still shows in the morning |
| 2026-09-29 | Robots act in 0.5 s steps inside the 0.1 s facility tick | 5× cheaper, still deterministic; an hour of facility time simulates in ~0.4 s |

## Gameplay directions (approved long-term, not started)

These all fit and can be combined; none is being built yet:

- **Assign & schedule work:** a work-order queue; decide which robot does what.
- **Monitor & respond:** watch feeds and readouts, spot problems, dispatch or intervene.
- **Talk to the robots:** messages/calls, replies and choices; relationships drive the story.
- **Investigate / uncover:** logs, files and footage reveal what the facility really is.

## Robots so far

| Robot | Build | Personality (profile) |
| --- | --- | --- |
| **Tinker** | Wheatley-style core on a tether, telescoping arms, drill-spin tool heads | Precise, quick, curious: 3 Hz body, 0.9x reach, 1.15x amplitude |
| **Hauler** | Heavy hanging body, neck + head, long two-segment excavator arms, clamp claws | Brute labour: 1.2 Hz underdamped body (swings, winds up), 1.8x reach, plays 1.25x slower |
| **Ogre** | Huge ceiling-mounted spherical core (drawn 8x), dark greys + yellow light rings, a searchlight eye with a light cone, one knuckle-boom crane with a hanging grab | Planet-slow: 0.35 Hz core that turns only part-way (the eye does the rest), 3x reach, plays 1.8x slower. Stationary |

All are placeholder primitives; final models will be rigid parts from Blender.
