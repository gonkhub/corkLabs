# corkLabs: status and roadmap

Where things stand and what's next. Update this at the end of every working
session. Design reasons live in [DESIGN.md](DESIGN.md); how-to in the
[README](../README.md).

*Last updated: 2026-09-29*

## Status

| Area | State | Tested |
| --- | --- | --- |
| VR recorder (mirror robot, robot select, calibration, auto-bake, play-along, punch-in) | Working | In headset by the user; "very smooth" |
| Cleanup + baking (smoothing, loop closing, gap repair, per-robot profiles) | Working | Automated tests |
| Robots: Tinker, Hauler (placeholder primitives) | Working | Tests + screenshots; profiles still need tuning by eye |
| Robot Lab, demo facility (flat screen) | Working | By the user, after the relaunch-without-VR fix |
| Editor **Takes** panel | Working | By the user |
| **Take naming** window + `takes/<robot>/` layout | Working | By the user (first naming session committed) |
| **Facility time** (clock, scheduler, journal, save, shifts, F1 dev panel) | Working, baseline | Automated tests + demo screenshot; user confirmed baseline |
| Robot behaviour (robots as facility systems) | **Not started** | |
| corkLabs desktop OS | **Not started** | |

## Branches and pull requests

Everything from 2026-09-29 is merged into `main` (PRs
[#1](https://github.com/gonkhub/corkLabs/pull/1) take naming and
[#2](https://github.com/gonkhub/corkLabs/pull/2) facility time + docs).
No open branches. Start new work on a fresh branch from `main`.

## Next up

1. **Robot behaviour scaffolding.** Make robots facility systems: they pick up
   work, react to supervisor orders, to each other and to the environment,
   and their decisions show in the journal. Design questions to settle first:
   - Decision model: utility scores, behaviour trees, or goal/plan (GOAP)?
   - What does a robot *want* (needs such as power, maintenance, "comfort")?
   - How do orders work: direct commands, suggestions they can refuse, or priorities?
   - How do robots perceive each other and the environment (events, sensors, a shared blackboard)?
   - How does sim state drive visuals (which clip plays, rail travel) when time only moves on player actions?
2. **One shift, start to end** (the first playable slice) on top of 1.
3. **corkLabs desktop OS** shell: windows, camera feeds, a message app, the facility clock.

## Backlog

- Tune Tinker's and Hauler's profiles in Robot Lab (weights, damping, reach).
- Upgrade Godot 4.3 → 4.6+ (needed for the built-in IK modifiers, for reactive IK).
- Real robot models (rigid parts from Blender).
- GitHub Actions to run `tests/` on every PR.
- Use a GitHub noreply email for future commits (commits currently show a personal address; the repo is public).

## Known issues

- Flat scenes (Robot Lab, demo) restart themselves without VR, so the editor's
  Stop button and Output panel don't reach them. Logs go to
  `%APPDATA%\Godot\app_userdata\corkLabs\logs\godot.log`.
- Hauler still reads a little leggy from straight in front.
- The recorder bakes when you press stop; long takes may hitch briefly in the headset.
- Demo robots still move on real time (they aren't facility systems yet).
