# corkLabs: status and roadmap

Where things stand and what's next. Update this at the end of every working
session. Design reasons live in [DESIGN.md](DESIGN.md); how-to in the
[README](../README.md).

*Last updated: 2026-09-30*

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
| **Camera audio**: Feed/Voices/World/UI buses, one listening camera, room-aware 3D sounds, robot motor hum, Cameras mute, Terminal `sound` auditions | **New framework, needs a listen** | Automated tests + screenshot (not checked by ear) |
| **Corporate**: corkHQ panel (unclosable), shift reviews + budget, Requisitions app, software packages via the Terminal | **New framework, needs a look** | Automated tests + screenshots (chime not checked by ear) |
| **Ogre**: massive stationary crane core in a new hangar (light cone eye, one crane arm), `stationary`/`reach` traits, freight jobs, two hangar cameras | **New, needs a look** | Automated tests (`test_ogre.gd`) + screenshots; not tried in VR |

## Branches and pull requests

Four new branches, **stacked** (each builds on the one before; the first
three from the 2026-09-29 evening session, the fourth from 2026-09-30). Push all three, then open the PRs in order; merge
them in order (after #1 is merged, #2's diff on GitHub shows only its own
commits, and so on).

| Order | Branch | What | Needs from you |
| --- | --- | --- | --- |
| 1 | `feature/robot-behaviour` | Robots as facility systems: utility scores, power + purpose, work board, orders + push-back, `RobotView`, dev panel pages. Also carries the earlier unpushed ROADMAP commit from `docs/roadmap-after-merge` | Run the demo; open `robots/*/<id>_traits.tres` in the Inspector |
| 2 | `feature/facility-content` | `FacilityPlant`: devices, faults, chains, salvage hand-off, shift reports; 3D props coloured by state | Watch the demo for a shift (F7 / Shift+F6); do the props read? |
| 3 | `feature/desktop-os` | The corkLabs OS (`os/desktop.tscn`); 3D world split into `game/facility_world.tscn`; `Supervisor` actions | Play it: log on, give orders, break things (F9), log off/on |
| 4 | `feature/os-buildout` (PR #3, contains 1-4) | F5 boots into the OS; Cameras = observation only (PTZ, grid, 4th camera); window snapping/maximise; layout memory; notification centre; Terminal, Settings, Handbook | Click around: drag windows to edges, pan cameras, try `help` in the Terminal |
| 5 | `feature/rooms-and-speech` | Rooms + rail network with route caveats, bigger Hauler, robot speech framework; Messages/Handbook/demo removed | Watch the camera grid through a Wait; `block`/`unblock` routes in the Terminal; listen to the voices |
| 6 | `feature/stability-and-corporate` | Software stability, corkHQ, requisitions + budget, software packages; tracker cam removed | Let a robot go unstable (Wait, don't give it work); find the software server; order something |
| 7 | `feature/camera-audio` | Camera feed audio: bus layout, listener = the camera you watch, `FacilitySound` with room-aware attenuation, motor hum, Mute button (M), feed volume, `sound` auditions | Open the Audio tab in the editor; in Cameras, `sound loop tone 10` in the Terminal and switch cameras; hover grid feeds; press Mute |
| 8 | `feature/ogre` (merged, PR #7) | Ogre, the stationary crane robot, and its hangar | Watch the Hangar cameras through a Wait; perform for Ogre in the recorder (right hand = crane, left trigger = winch) |

`docs/roadmap-after-merge` is now contained in branch 1 and can be deleted
after that merges. Claude creates the PRs with `gh` once the branches are pushed.

All tests pass on each branch (`tools\run_tests.ps1`; 16 test files on the last one).

## Things to try first (about 15 minutes)

1. Press **F5** (the game now boots into the OS). Skip the boot text, **Log on**.
2. Open **Cameras**: drag to pan, scroll to zoom, G for the grid. Open **Units**
   beside it (drag a window to the screen edge to snap). Press **Wait → 1 hour** (an alarm stops it early) and
   watch the robots pick work, recharge, get restless.
3. Press **F9** (dev) a few times to post jobs, or wait for faults. When an
   **ALARM** toast appears, open **Plant**, then **Work Orders**, and order a
   robot onto the job. Try ordering Tinker onto heavy work (it refuses), or
   a robot low on power (it recharges first).
4. **Messages** shows the robots' answers; **Facility Log** has every
   decision with its reasons.
5. Try the **Terminal** (`help`, `status`, `order tinker recharge`).
6. Log off, close, reopen: it resumes at the same facility minute, with your windows where you left them.

## Decisions waiting for you

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

0. **Try the rooms and speech framework** (branch 5), then decide what fills
   the rooms and how robots should sound.

1. **Your pass over the three branches** (above), and tuning traits/plant
   rates by eye.
2. **One shift, start to end** (the first playable slice): a shift brief at
   log on, a goal (throughput/quota), incidents that push the robots over,
   and an end-of-shift report screen. Most of the pieces now exist.
3. **Talking to the robots**: grow Messages into dialogue (choices that cost
   time, robots' opinions of the supervisor, maybe the "trust" need we left
   out).
4. **Robots reacting to each other** more directly (a robot noticing another
   stalled or overloaded; asking for help across rails).

## Backlog

- Tune Tinker's and Hauler's motion profiles in Robot Lab (weights, damping, reach).
- Upgrade Godot 4.3 → 4.6+ (needed for the built-in IK modifiers, for reactive IK).
- Real robot and facility models (rigid parts from Blender); props are placeholders.
- More robots (a third body type), and rails that connect.
- Simulation speed: 1 facility hour ≈ 0.4 s to compute (fine now; long waits
  hitch slightly). Could skip idle ticks if it grows.
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
