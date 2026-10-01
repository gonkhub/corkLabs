# corkLabs: status and roadmap

Where things stand and what's next. Update this at the end of every working
session. Design reasons live in [DESIGN.md](DESIGN.md); how-to in the
[README](../README.md).

*Last updated: 2026-10-01*

## Status

| Area | State | Tested |
| --- | --- | --- |
| VR recorder (mirror robot, robot select, calibration, auto-bake, play-along, punch-in) | Working | In headset by the user; "very smooth" |
| Cleanup + baking (smoothing, loop closing, gap repair, per-robot profiles) | Working | Automated tests |
| Robots: Tinker, Hauler (placeholder primitives) | Working | Tests + screenshots; profiles still need tuning by eye |
| Robot Lab, demo facility (flat screen) | Working | By the user, after the relaunch-without-VR fix |
| Editor **Takes** panel, **take naming** window | Working | By the user |
| **Facility time** (clock, scheduler, journal, save, shifts, F1 dev panel) | Working | Automated tests; user confirmed baseline |
| **Robot behaviour**: utility-AI robots with power + purpose needs, work board, orders they can push back on | **New, needs a look** | Automated tests + screenshots |
| **Facility content**: pods, filters, coolant, relay, bays; faults chain; salvage hand-off between robots | **New, needs a look** | Automated tests + screenshots |
| **corkLabs desktop OS**: login, windows, taskbar with facility clock, 6 apps, toasts | **New, needs a look** | Automated tests + screenshots |
| **OS build-out**: boots into the OS, observation-only Cameras with pan/tilt/zoom + grid, snapping/maximise, remembered layout, notification centre, Terminal, Settings | In PR #3 | Automated tests + screenshots + simulated clicks |
| **Rooms + rail network**: 4 rooms (huge main hall), routes with caveats (narrow, blocked, slow), re-routing, 3D world built from the layout, bigger Hauler | **New framework, needs a look** | Automated tests + screenshots |
| **Robot speech**: floating CCTV text + voice blips; lines by trigger/condition in `barks.txt`; robot-to-robot exchanges | **New framework, needs a look** | Automated tests + screenshots (sound not checked by ear) |
| **Software stability**: independence, whims, fixations, critical errors (crash/glitch), sabotage, reboots | **New framework, needs a look** | Automated tests + journal read-throughs |
| **Dark facility + night vision**: no room lights, robot status LEDs, unlit signs; N / checkbox switches feeds to IR; feeds locked to 30 fps | **New, needs a look** | Automated tests + screenshots |
| **Camera audio**: Feed/Voices/World/UI buses, one listening camera, room-aware 3D sounds, robot motor hum, Cameras mute, Terminal `sound` auditions | **New framework, needs a listen** | Automated tests + screenshot (not checked by ear) |
| **Corporate**: corkHQ panel (unclosable), shift reviews + budget, Requisitions app, software packages via the Terminal | **New framework, needs a look** | Automated tests + screenshots (chime not checked by ear) |
| **Ogre**: massive stationary crane core in a new hangar (light cone eye, one crane arm), `stationary`/`reach` traits, freight jobs, two hangar cameras | **New, needs a look** | Automated tests (`test_ogre.gd`) + screenshots; not tried in VR |
| **Shifts campaign**: three shifts as one timeline (brief, clock in, duties, scripted events, end of shift, the night); shift 1 is a tutorial; **no Wait**; endings archived ("end of this build") | **Reworked, needs a play** | `test_story.gd`, `test_secrets.gd` + screenshots |
| **Pushback**: corporate directives with deadlines; Pell escalating (warning, explain yourself, Compliance + targeted audit); the uplink blind spot (Hauler's "accident") | **New, needs a play** | Automated tests + screenshots |
| **A facility that fights back**: stuck doors, dead cameras, the uplink; repairs need parts (jobs stop without them); unit wear, seizing, manual reboots, services; units' requests; per-shift pressure | **New, needs a play and tuning** | Automated tests, unattended balance runs, screenshots |
| **Getting fired**: standing, suspicion, audits, strikes, catastrophes; retry the shift from its checkpoint or start over; personnel file across runs | **New, needs a play** | Automated tests |
| **Terminal you learn** + OS file system (former supervisors' homes, memos, logs; hidden/encrypted/purged files) + Files app | **New, needs a play** | Automated tests + screenshots |
| **Run it from the cameras** (third pass): hover outlines, click menus on units and machines; Dispatch; stable units only do what they're told, unstable ones choose for themselves; night autopilot; parts taken at ordering (or patch it); Units/Work Orders apps removed; talking moved into Cameras | **New, needs a play** | Automated tests + two screenshots (menus, outline); hover/click not tried by hand |
| **Talking**: conversation scripts for Tinker, Hauler, Ogre (a unit's menu in Cameras: Talk, or the Terminal's `talk`) and Liaison Pell (corkHQ Reply) | **New, first-pass writing** | Automated tests + screenshots |
| **Night Run** (hidden arcade game with two secrets), the **maintenance account** (auditctl, hqctl, unitctl, pkgctl, podctl), **pods** | **New, needs a play** | Automated tests + screenshots |
| **Fourth pass + macro pass**: errands, roles, routine work and chores (pod waste, compactor, rails), inspections by units, relay -> uplink, hqctl disable, Terminal parity, ir-vision package, cameras as corporate's eyes, trust from treatment, night-watch + overclock, DevTools | **New, needs a play** | Automated tests (19 files) + simulated play (efficient supervisor: 7/8 seeds finish with 1.5-4 h spare a shift; a heavy snooper gets fired on day 3 in 2/4) |
| **More actions**: Duties app, Plant inspect, object menus (order maintenance, patch, diagnose, service, answer requests, pump coolant), express shipping, Recycle Bin, Notes, cp/grep/find/who/ps | **New** | Automated tests |
| **Unit behaviour pass**: Ogre starts broken (Pell, Form C-9, a free core, Hauler + Tinker); Forms app; dialogue checker; units face the camera on the link; a repaired camera's greeting; props (wrench, radio, crate), habits, contextual exchanges; dead Ogre looks dead; Notes pages/find/colours; camera hover cards + pop-out | **New, needs a play** | Automated tests (21 files) + screenshots (greeting, dead Ogre, props, Notes, hover card, pop-out) |
| **Ogre hand-off chain** (deliveries arrive as crates), **crated robots** (activate a new unit), **GitHub Actions** CI | **New** | Automated tests; CI runs once pushed |

## Branches and pull requests

Everything up to the dark facility, camera audio and Ogre is merged into
`main` (PRs #3-#7). The old feature branches (`feature/robot-behaviour` ...
`feature/dark-facility`, `docs/roadmap-after-merge`, `test/integration`) can
be deleted.

| Branch | What | Needs from you |
| --- | --- | --- |
| `feature/shifts-and-secrets` (2026-09-30, from `main`) | Two passes. **First:** Wait removed; shifts campaign; getting fired; the learned Terminal; file system and lore; conversations; Night Run; maintenance account; Duties/Files/Notes/Bin apps; Reply to Pell; perform cues; crate chain; crated robots; CI. **Second (after your notes):** pacing x3-6; locked homes + trust chains; parts, wear, requests, new failures; directives, Pell escalation, the uplink; shift 1 as orientation; endings archived. **Third (2026-10-01):** run the facility from the cameras (click menus, Dispatch, obedient stable units, night autopilot); reprimands that shake corkHQ hard; directives never missed overnight; starting stock. **Fourth (2026-10-01, from your play notes):** errands, pick the unit, talk and requests on camera, roles, Ogre's hangar machines, routine work and chores, pod waste and the compactor, inspections by units, the relay powering the uplink, hqctl disable, Terminal parity, night vision as a package, balance from simulated play. **Macro pass:** the cameras are corporate's eyes, trust from treatment, packages that all work (night-watch, overclock), remote reboot frees seized units, catalogue cuts, DevTools (`dev`). **Unit behaviour pass:** Ogre broken + Form C-9, dialogue sanity, facing the camera, the camera greeting, props/habits/exchanges, Notes upgrade, camera hover cards + pop-out. **Play-note fixes:** safe DevTools skips, Pell reprimand categories, no orders between units, protected quest lines, units wait for your answer, camera repair spots, cameras not alarms, the gate softlock, Plant colours, `order` known, Reply closes on uplink loss, no Make urgent | Push it; Claude opens the PR. Then play shift 1 (see below) and read [STORY.md](STORY.md) |

All tests pass (`tools\run_tests.ps1`; 22 test files; the per-file timeout is 300 s).

## Things to try first (about 45 minutes)

1. F5, **Log on** (an older save is replaced). Read **Shift 1's brief**,
   **Clock in**. Open **Duties**: it's your orientation checklist.
2. Work through it: `cat welcome.txt` in the Terminal, then Cameras: hover
   things, click a leaking pipe (Order maintenance), click a unit (its
   menu), inspect something, order parts, answer a unit's request (REQUESTS
   on the taskbar takes you to the unit).
3. Let the morning happen: a leak (07:10) with too few clamps, a dead camera
   (09:00), the dock door sticking (10:20), Hauler seizing (11:20). Watch
   corkHQ's **directives** pile on (Duties shows them, with deadlines).
4. Snoop and see what happens: `ls /home` (locked), `cat` the open ones, play
   Night Run, talk to Tinker more than once. Pell notices, then wants an
   explanation (Reply), then calls Compliance.
5. Clock out, and see the night summary in the next brief. Notice what the
   end-of-shift screen says about directives and the units' requests.
6. The spoiler map is [STORY.md](STORY.md): the chains, the costs, the
   pushback, the uplink trick, and the clips to perform in VR.

## Decisions waiting for you

From the second pass:

- **Is the pressure right?** Shift 1 orientation pressure 0.65, shift 2 1.0,
  shift 3 1.15 (`Campaign.PRESSURE`); fault rates in `FacilityPlant.KINDS`;
  starting stock in `Requisitions.START_STOCK`. In unattended test runs the
  clamps run out mid-morning and coolant dries up by midday without orders;
  a supervisor who never books services sees seizures pile up by shift 2-3.
- **Costs**: `Facility.COST` (3/5/15/45 min), reading x3, inspect/diagnose 30,
  Night Run 30. Enough that a shift can't hold everything?
- **Pell's thresholds** (`Oversight.ESCALATE`) and how much each level costs.
- **The uplink trick**: strong (a blind window of 30-60 min). Too strong? Should
  the repair need a part so blackouts can last longer (riskier)?
- **Trust**: 3 conversations two hours apart for Okafor's password; Ogre 2,
  Hauler 2. Too slow / too fast?
- **Wear**: seizing from 50% wear; units free themselves after 2 h; services
  reset to 8%. Servo bundles are 200 cr for two.
- **Trust from treatment** amounts (`Knowledge.nudge_trust` callers): can a
  caring supervisor reach Okafor's password (trust 3) on day 1? Should they?
- **Blind spots**: one camera each covers the workshop and the maintenance
  room, so those are the easiest rooms to blind. Intended?
- **Endings** are parked in `docs/archive/endings.txt` (memory note too).

From the first pass (still open):

- **The lore**: names (Hollis, Marrow, Vance, Kim, Okafor, Pell), "the pods
  hold people / transferred = put in a pod", the tone of the files.
- **Three shifts** enough? **What carries across runs** (only the player's
  memory, the personnel file, Night Run scores and the Notes app)?
- **The Terminal's starting commands** (help, status, clear, ls, cd, cat, pwd).
- **Clips to perform**: seven named in STORY.md, plus ideas for the new systems.

Earlier:

- **Camera audio**: how loud through walls (-30 dB now), whether robot voices
  should become positional too, whether the grid should hear the last-opened
  camera instead of the hovered one, and what goes on the Feed bus (a "CCTV
  mic" band-pass? room reverbs per camera?).
- **Which sounds come first**: room tone per room, device hums/alarms on the
  plant props, passage shutters. Each is a `FacilitySound` on the thing.
- **Ogre**: is the hangar where it should be (south of the main hall, 50 x 40 m)?
  What should it really lift (freight is a placeholder)? Should it hand things
  to the rail robots at the loading bay (a chain, like salvage)? Should it be
  the preferred robot for hangar work (now Hauler sometimes rides in and takes
  the loading bay first)? Its lines are a first pass (end of `barks.txt`).
- **Ogre's look**: ceiling-hung (like the others) or cradled on the floor? The
  eyelid is a flat shutter; the crane's hook is a simple two-jaw grab.

- **What each software package should really do** (packages.txt; three are wired).
- **Crated robots**: how a delivered unit gets activated (a new robot in the facility?).
- **How visible sabotage should be** to the supervisor (now: only the Facility Log, and corkHQ sometimes notices).
- **corkHQ's voice**: tone and how often it nags (hq_lines.txt, CHECK_EVERY).

- **What goes in the rooms**, and **what the rooms are for** (they're empty
  space now). More rooms? Which connect to which, and with what catches?
- **Robot voices**: blips are placeholders. Recorded samples, a synth, or a
  mix? Should the Facility Log keep showing speech (it's there for debugging)?
- **The lines** in `game/speech/barks.txt` are a first pass: rewrite freely.
- **When should route blocks happen** besides the freight gate jamming
  (debris in ducts, lockdowns, shift changes, story events)?

- **Boot screen text**: placeholder firmware lines ("Unit link: TINKER ... online").
  Rewrite freely; they're `BOOT_LINES` in `os/desktop.gd`.
- **Handbook voice**: plain and friendly right now. Should it read like a
  corporate onboarding document (a place to plant story hints)?
- **More cameras / rooms**: four cameras cover the one room. When the
  facility grows, which rooms come next?
- **Balance**: a normal day is calm (~86% throughput, robots keep up).
  Should the baseline be harder, or should pressure come from story events?
- **Robot voice**: replies are short and dry ("On it.", "No. 'Clear debris'
  is heavy work; I'm not built for it."). Is that the tone you want?
- **Hauler's stoicism / Tinker's restlessness**: they're in the traits
  files; do they read as characters when you watch them?

## Next up

0. **Use DevTools** (`dev` in the Terminal) to jump around: end shifts,
   break things, set trust, run any scripted event.
1. **Play shift 1** as a new supervisor, then a snooping run, and set the
   pressure/costs/thresholds above.
2. **The acting pass**: the seven story clips, `act_wave_camera`, the
   eight habit clips (`idle_*`, see STORY.md), plus a seize, a manual
   reboot, Hauler's "accident", unpacking a crate.
3. **More shift 2/3 content**: events, files that appear later, conversation
   branches that use trust; what the overnight summary should say.
4. **Endings**, when the loop feels right (start from the archive).
5. **Sound for the systems**: alarms per failure, Night Run, the uplink going
   dark, a seized unit.

## Backlog

- Tune Tinker's and Hauler's motion profiles in Robot Lab (weights, damping, reach).
- Upgrade Godot 4.3 → 4.6+ (needed for the built-in IK modifiers, for reactive IK).
- Real robot and facility models (rigid parts from Blender); props are placeholders.
- More robots (a third body type), and rails that connect.
- Simulation speed: 1 facility hour ≈ 0.4 s to compute. The night between
  shifts (16 h) is spread over frames; could skip idle ticks if it grows.
- GitHub Actions to run `tests/` on every PR.
- Use a GitHub noreply email for future commits (commits currently show a personal address; the repo is public).

## Known issues

- F5 (the OS) starts a VR session for a moment and restarts without VR, like
  the other flat scenes, when the headset is on. An exported game should ship with OpenXR off.
- Flat scenes (Robot Lab, demo, desktop) restart themselves without VR, so
  the editor's Stop button and Output panel don't reach them. Logs go to
  `%APPDATA%\Godot\app_userdata\corkLabs\logs\godot.log`.
- Floating 3D labels are tiny in the smaller camera windows.
- The main hall is huge, so from the hall cameras robots are small; zoom in, or use Cam 3 (tracks Hauler).
- Speech text is drawn over walls (feeds check the robot's room, not line of sight).
- An old facility save (before rooms) is discarded: a new facility starts.
- Hauler still reads a little leggy from straight in front.
- The recorder bakes when you press stop; long takes may hitch briefly in the headset.
- Ogre's baked clips don't aim the crane at its real work spot (no reactive IK
  yet), so the hook works near, not exactly on, the crates.
- Ogre in the recorder is shown at 1x (a 1.5 m core); its crane reaches about 3 m.
