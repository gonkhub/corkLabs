# corkLabs: status and roadmap

Where things stand and what's next. Update this at the end of every working
session. Design reasons live in [DESIGN.md](DESIGN.md); how-to in the
[README](../README.md).

*Last updated: 2026-09-29 (evening session)*

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

## Branches and pull requests

Three new branches from the 2026-09-29 evening session, **stacked** (each
builds on the one before). Push all three, then open the PRs in order; merge
them in order (after #1 is merged, #2's diff on GitHub shows only its own
commits, and so on).

| Order | Branch | What | Needs from you |
| --- | --- | --- | --- |
| 1 | `feature/robot-behaviour` | Robots as facility systems: utility scores, power + purpose, work board, orders + push-back, `RobotView`, dev panel pages. Also carries the earlier unpushed ROADMAP commit from `docs/roadmap-after-merge` | Run the demo; open `robots/*/<id>_traits.tres` in the Inspector |
| 2 | `feature/facility-content` | `FacilityPlant`: devices, faults, chains, salvage hand-off, shift reports; 3D props coloured by state | Watch the demo for a shift (F7 / Shift+F6); do the props read? |
| 3 | `feature/desktop-os` | The corkLabs OS (`os/desktop.tscn`); 3D world split into `game/facility_world.tscn`; `Supervisor` actions | Play it: log on, give orders, break things (F9), log off/on |

`docs/roadmap-after-merge` is now contained in branch 1 and can be deleted
after that merges. Claude creates the PRs with `gh` once the branches are pushed.

All tests pass on each branch (`tools\run_tests.ps1`, 12 test files).

## Things to try first (about 15 minutes)

1. Open `os/desktop.tscn`, **F6**, **Log on**.
2. Open **Units** and **Cameras**. Press **Wait → 1 hour** (an alarm stops it early) and
   watch the robots pick work, recharge, get restless.
3. Press **F9** (dev) a few times to post jobs, or wait for faults. When an
   **ALARM** toast appears, open **Plant**, then **Work Orders**, and order a
   robot onto the job. Try ordering Tinker onto heavy work (it refuses), or
   a robot low on power (it recharges first).
4. **Messages** shows the robots' answers; **Facility Log** has every
   decision with its reasons.
5. Log off, close, reopen: it resumes at the same facility minute.

## Decisions waiting for you

- **What should cost facility time on the desktop?** Right now orders and
  priority changes cost 2 min, Wait passes time, and opening apps/cameras is
  free. Should looking at a camera or the log cost time (the design table
  says "opening a feed: 5 minutes")?
- **Make the desktop the main scene?** F5 still runs the VR recorder (handy
  for recording). The game will eventually start at `os/desktop.tscn`.
- **Balance**: a normal day is calm (~86% throughput, robots keep up).
  Should the baseline be harder, or should pressure come from story events?
- **Robot voice**: replies are short and dry ("On it.", "No. 'Clear debris'
  is heavy work; I'm not built for it."). Is that the tone you want?
- **Hauler's stoicism / Tinker's restlessness**: they're in the traits
  files; do they read as characters when you watch them?

## Next up

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

- Flat scenes (Robot Lab, demo, desktop) restart themselves without VR, so
  the editor's Stop button and Output panel don't reach them. Logs go to
  `%APPDATA%\Godot\app_userdata\corkLabs\logs\godot.log`.
- Floating 3D labels are tiny in the smaller camera windows.
- Hauler still reads a little leggy from straight in front.
- The recorder bakes when you press stop; long takes may hitch briefly in the headset.
