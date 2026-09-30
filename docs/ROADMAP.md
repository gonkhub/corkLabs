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
| **Dark facility + night vision**: no room lights, robot status LEDs, unlit signs; N / checkbox switches feeds to IR; feeds locked to 30 fps | **New, needs a look** | Automated tests + screenshots |
| **Camera audio**: Feed/Voices/World/UI buses, one listening camera, room-aware 3D sounds, robot motor hum, Cameras mute, Terminal `sound` auditions | **New framework, needs a listen** | Automated tests + screenshot (not checked by ear) |
| **Corporate**: corkHQ panel (unclosable), shift reviews + budget, Requisitions app, software packages via the Terminal | **New framework, needs a look** | Automated tests + screenshots (chime not checked by ear) |
| **Ogre**: massive stationary crane core in a new hangar (light cone eye, one crane arm), `stationary`/`reach` traits, freight jobs, two hangar cameras | **New, needs a look** | Automated tests (`test_ogre.gd`) + screenshots; not tried in VR |
| **Shifts campaign**: three shifts as one timeline (brief, clock in, duties, scripted events, end of shift, the night, endings); **no Wait** | **New, needs a play** | `test_story.gd`, `test_secrets.gd` + screenshots |
| **Getting fired**: standing, suspicion, audits, strikes, catastrophes; retry the shift from its checkpoint or start over; personnel file across runs | **New, needs a play** | Automated tests |
| **Terminal you learn** + OS file system (former supervisors' homes, memos, logs; hidden/encrypted/purged files) + Files app | **New, needs a play** | Automated tests + screenshots |
| **Talking**: conversation scripts for Tinker, Hauler, Ogre (Terminal `talk`, Units Talk) and Liaison Pell (corkHQ Reply) | **New, first-pass writing** | Automated tests + screenshots |
| **Night Run** (hidden arcade game with two secrets), the **maintenance account** (auditctl, hqctl, unitctl, pkgctl, podctl), **pods** | **New, needs a play** | Automated tests + screenshots |
| **More actions**: Duties app, Plant inspect / request maintenance / spare parts, Units diagnose | **New** | Automated tests |

## Branches and pull requests

Everything up to the dark facility, camera audio and Ogre is merged into
`main` (PRs #3-#7). The old feature branches (`feature/robot-behaviour` ...
`feature/dark-facility`, `docs/roadmap-after-merge`, `test/integration`) can
be deleted.

| Branch | What | Needs from you |
| --- | --- | --- |
| `feature/shifts-and-secrets` (2026-09-30, from `main`) | Wait removed; shifts campaign; getting fired; the learned Terminal; file system and lore; conversations; Night Run; maintenance account; Duties/Files apps; Plant and Units actions; Reply to Pell; perform cues for VR clips; test runner fix | Push it; Claude opens the PR. Then play a shift (see below) and read [STORY.md](STORY.md) |

All tests pass (`tools\run_tests.ps1`; 19 test files).

## Things to try first (about 30 minutes)

1. Delete the old save first if you like (it's an older version and will be
   replaced anyway): F5, **Log on**. You're at **Shift 1's brief**. Read it,
   **Clock in**.
2. Open the **Terminal**: `help` (only a handful of commands), `ls`,
   `cat welcome.txt`, `help` again. Open **Duties** and do one.
3. Poke around: `cd /home`, `ls`. You're told not to. Try it anyway, and
   watch corkHQ. `talk tinker`. The Units app now has Talk.
4. Open **Files** and browse. Find the game. Play a round (arrow keys).
   Read the NO ENTRY sign.
5. Try to get fired (dev: F6 with Shift passes an hour; a pile of violations
   + a few hours of audits will do it). Retry the shift.
6. Do a whole shift, then **Clock out** and watch the night pass.
7. The spoiler map is [STORY.md](STORY.md): every secret, how it chains, what
   everything costs, and the clips to perform in VR.

## Decisions waiting for you

New this session (shifts and secrets):

- **Pacing**: a shift is 480 facility minutes. Duties fill about 80-110,
  reading all the files about 45, a conversation 5-15, orders 2 each, Night
  Run 10 a run. A thorough player still has hours left; a quick one will lean
  on Night Run. Options: raise costs (`Facility.COST`, per-action minutes),
  shorten shifts (`ShiftSchedule.shift_hours`), more duties, or keep Night
  Run as the "sanctioned" time sink.
- **Firing thresholds**: standing starts 60 (reviews A +15 ... F -25, duties
  +3..6 / -5 undone); audits find something at (suspicion - 25)% an hour; two
  catches = dismissed. All constants in `oversight.gd` / `campaign.gd`. Too
  harsh? Too soft?
- **The lore**: names (Hollis, Marrow, Vance, Kim, Okafor, Pell), the "pods
  hold people / transferred = put in a pod" reveal, the tone of the files.
  All in `game/story/`; rewrite freely. Is it too dark / too early?
- **Three shifts** enough? Should the night be simulated (it is: things can
  go wrong overnight) or skipped?
- **The endings** (Awake, Transferred, Witness, Promoted, Contract Renewed,
  Probation): which ones do you want, and what should Awake lead to?
- **What carries across runs**: only the player's memory (and the personnel
  file). Should anything else carry (e.g. Night Run high scores already do)?
- **The Terminal's starting commands**: help, status, clear, ls, cd, cat, pwd.
  Too few? Too many?
- **Pell**: her voice, and whether replying to her should cost standing when
  you push her.
- **Clips to perform**: seven named in STORY.md. More moments worth acting?

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

1. **Play the new branch** (a shift or two, try to get fired, try to find
   things), then decide the pacing and firing numbers above.
2. **The acting pass**: record the seven story clips (STORY.md), and any
   idles/work clips the conversations make you want.
3. **Shift 2 and 3 content**: more events, more files that appear later
   (`#! shift: 2`), more conversation branches; the overnight summary could
   become its own little report.
4. **Robots reacting to each other** more directly (a robot noticing another
   stalled or overloaded; asking for help across rails).
5. **Sound for the story**: Night Run blips, the corkHQ mute, pod hum.

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
