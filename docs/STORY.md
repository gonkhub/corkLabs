# corkLabs: the story so far (SPOILERS)

Everything a player can find, how it's found, what it costs, and where it
lives, so it can be reviewed, rewritten and rebalanced. All of it is
first-pass writing, meant to be rewritten freely: every piece is a plain
text file, so no code changes are needed to change a line.

*Updated 2026-10-01 (third pass: run it from the cameras, roles, routine
work, errands, cameras as corporate's eyes, trust from treatment).*

## The shape of a run

One continuous timeline of **three shifts** (Day 1-3, 06:00-14:00). Each
shift: a **brief** (what corporate wants, what happened overnight, today's
duties) → **clock in** → play (time only moves when you act) → **14:00: end
of shift** (review, standing, duties, directives, how you treated the
units' requests) → **clock out** (the night passes, the units in standby)
→ next brief. After shift 3: **the end of this build** (the endings are
archived in `docs/archive/endings.txt` until they come back).

A shift is **480 facility minutes**, and everything costs time (table
below). Between duties, corporate's directives, the units' requests and
whatever breaks, a thorough supervisor has maybe an hour or two of their
own per shift. Nobody sees everything in one day.

| Shift | What it is |
| --- | --- |
| 1: Orientation | Tutorial duties walk you through the OS (onboarding, cameras, an order, an inspection, a requisition, answering a unit). Scripted incidents, one system at a time: a leak (07:10), a dead camera (09:00), the dock door sticking (10:20), Hauler seizing up (11:20), an output directive (12:30). Faults are gentler (pressure 0.65) |
| 2: The Purge | Okafor's home and account are purged at 12:00 (or when you confirm it). The relay blows, a door sticks, Tinker seizes, a camera dies. Normal pressure |
| 3: Audit | Compliance audits your terminal at 13:00 (strictness +25). The gate jams, a leak, a camera, Ogre seizes. Pressure 1.15 |

## Getting fired

| How | What triggers it |
| --- | --- |
| Performance | Standing reaches 0: bad reviews, undone duties, missed directives, Pell's Compliance, crashed units |
| Misconduct | Two audits catch you (hourly on duty; targeted ones when Pell escalates; the big one on shift 3) |
| Catastrophe | Coolant empty for 45 facility minutes, or throughput under 30% for an hour, on your watch |

Dismissed: **retry the shift** (from its brief) or **start over**. The
**personnel file** (`user://supervisor_archive.json`) remembers every run.
What carries between runs is what the player remembers: typed commands and
passwords work on a new save.

## Corporate pushes back

- **Directives** (`directives.gd`): every hour or so on duty corkHQ demands
  something with a deadline: inspect a device, diagnose a unit, get a job
  done, reach a throughput figure, file a report. Met: standing up. Missed:
  standing down (more than you gained).
- **Pell escalates** per kind of violation within a shift: *files* (former
  staff files, copies), *games* (Night Run), *talk* (unit conversations),
  *maint* (the maintenance account and its tools).
  1. a warning in the panel;
  2. a directive to **explain yourself** within 45 minutes (Reply → "About
     my activity": apologise, justify, or refuse);
  3. Compliance: standing -6 and a **targeted audit** half an hour later.

  | Kind | Level 1 / 2 / 3 at |
  | --- | --- |
  | files | 1st / 3rd / 5th |
  | games | 1st / 2nd / 4th |
  | talk | 3rd / 6th / 10th |
  | maint | 1st / 2nd / 3rd |

## Avoiding corporate: blind spots

**The cameras are corporate's eyes.** What happens in a room (talking to a
unit, a unit's "accident" or sabotage) is only on the record if a working
camera covers that room. A dead camera is a blind spot: the Code of Conduct
says the cameras record, and that an out-of-service camera must be repaired
without delay. The terminal (files, accounts, tools) is audited whatever the
cameras see. One camera covers the workshop and the maintenance room each.

**The uplink.** corkHQ sees the facility through one **uplink relay** in the
workshop (the facility map memo and `ps` both mention it). While it's down:
no suspicion, no audit trail, no audits, no Pell, no new directives. The
corkHQ panel goes dark and holds its messages. Corporate sees an outage,
wants it back within the hour (a directive), and every repeat outage adds
suspicion (+5 per repeat). Ways down:
- **The relay.** A blown fuse left for 20 minutes flattens the uplink's
  battery; a new fuse brings it back. No uplink job: fix the relay (Tinker).
- **Hauler** (trust 2, the uplink known): "Could it have an... accident?"
  If the **workshop camera** is working, Hauler warns you it'll be seen, and
  if you go ahead, corporate sees a unit wreck the uplink on tape
  (suspicion +15). Kill the camera first.
- **`hqctl disable`** (maint): cut it by hand; `hqctl enable` restores it.
- Rarely on its own.

Other ways to deal with corporate, as maint: `auditctl purge` (once a
shift), `kill 45` (auditd restarts in 0.3 s, and that's noticed).

## The facility

- **Routine work is most of it** (no parts, just time and a little wear):
  pods (Tinker), filters (Hauler), **pod waste** (fills about once a day,
  unevenly: Hauler takes it to the hangar), the **waste compactor** (fills
  with waste and debris: room on day 1, full by day 2: Ogre empties it),
  **rail grime** (slows every unit: Hauler), freight (Ogre). Near-full waste
  bins make the units grumble; overflowing, they wear on every unit's
  software. **Chores** (waste, the compactor, the rails) wait for you: the
  night crew only keeps the facility alive (night-watch changes that).
- **Breakdowns** use parts: leaks (clamps; coolant drains, the facility
  heats, hot pipes leak more), the relay (fuses; slow charging, then the
  uplink), the freight gate (actuators), cameras (modules). Doors stick
  (no part: Hauler or Tinker frees them). A proper repair holds at least
  8 hours; a patch (no part) holds 2-5.
- **Nothing is done until you say so.** A stable unit only does jobs you
  order (Cameras: click the thing, Order maintenance, pick the unit) or
  the one you send it to; then it's an **errand**: no time passes when you
  order, the clock runs while you watch it work, and stops when it's done.
  A unit below stable picks its own work and starts ignoring you.
- **Roles:** Tinker (precision; the only one who services or reboots a
  unit), Hauler (heavy work and the rounds), Ogre (the hangar: freight, the
  coolant feed, the compactor).
- **Inspecting** is a unit's errand: it goes, looks and reports back
  (cameras: Plant or the Terminal, `inspect cam_5`).
- **Wear:** past 50% a unit can seize; Tinker reboots it by hand, the
  remote-reboot package frees it from the desk, or it frees itself after
  two hours (and trusts you less). Services: Tinker, a servo bundle.
- **Requests:** a unit that wants something pings (toast, REQUESTS,
  "ASKING" on its camera) and asks out loud when you watch its feed; the
  answers are buttons under the picture (or `requests` / `answer`).
  Requests about things you've already dealt with are withdrawn. Ignored
  ones cost it stability and trust.
- **Trust** (0-5) grows with conversations and with how you treat a unit:
  answering it, servicing it, keeping it working. Ignoring, overruling and
  leaving it seized cost it.
- **Everything the cameras do, the Terminal does** (for when a camera's
  out): `maintain`, `patch`, `inspect`, `order`, `diagnose`, `service`,
  `rescue`, `reboot`, `feed`, `requests`, `answer`, `talk` (in Cameras if a
  camera sees the unit, otherwise in the Terminal).
- **Night vision** needs the `ir-vision` package.
- **Dead cameras** are a nuisance, not an alarm (no ALARM light or toast).
- **The freight gate** (the workshop's way in): Hauler or Tinker can free
  it, so Hauler shut in the workshop isn't a dead end.
- **Ogre starts dead** (core fault E-417; its eye is dark). Until it's
  fixed, Hauler loads the coolant feed (heavy wear, and it says so) and
  very heavy crates (gate actuators, crated units) sit in the hangar.
  The chain: tell **Pell** (Reply: "Unit OGRE is down") -> she names **Form
  C-9** -> fill it in (Forms: designation OGRE, serial OGR-79-001 from
  `/sys/units/ogre.cfg`, fault E-417 from Diagnose) -> 75 min to file, 30-60
  min review -> a free express core (about 2 h) -> Hauler carries it to
  Ogre's service spot -> Tinker installs it. Day 1 duty: "Get Ogre back online".
- **Paperwork paces big things**: forms cost a lot of time, and need facts
  you've found and (ideally) written in your Notes.

## The cast

| Who | Where | What |
| --- | --- | --- |
| **You** | the terminal room (no door) | Supervisor #6, probationary |
| **Ms. Pell** | the corkHQ panel | Your liaison, logged in since 1979 (`who`). Reply to her from the panel |
| **Edwin Hollis** | `/home/ehollis` (maint only), pod 2 | Founding supervisor 1979-1994. Built the units, "built the dark". Found the wake sequence |
| **Ruth Marrow** | `/home/rmarrow` (maint only), pod 4 | 2003-2011. Made the maint account, wrote NIGHT RUN, talked to the units |
| **T. Vance** | `/home/tvance` (open) | 2014, three days |
| **J. Kim** | `/home/jkim` (open) | 2017, one shift |
| **Dele Okafor** | `/home/dokafor` (account dokafor; purged at 12:00 on shift 2), pod 3 | 2019 until two days ago. Said good morning to Tinker every day |
| **Tinker / Hauler / Ogre** | on the rails / the hangar ceiling | See their conversation scripts |
| **Tinker 2, Hauler 2...** | crated units you activate | Fresh firmware, no history, their own blank conversation |

## The chains (how the deep stuff is reached)

1. **Surface (shift 1):** your onboarding, the Code of Conduct (every rule
   is a hint: su, the maintenance account, the uplink, the pods), the memos
   (transfers, the facility map and the uplink), `/var/log/sessions.log`,
   `/sys/units/*.cfg`, Kim's and Vance's notes, the Recycle Bin, the Notes
   app's leftovers ("say good morning to Tinker (talk tinker)"). `ls /home`
   shows the locked homes.
2. **Okafor's account:** talk to Tinker on three occasions at least two
   facility hours apart (trust 3), having asked who was here before → ask
   if Okafor told it anything private → "their password was my name,
   backwards" → `su dokafor` / `reknit`. Only until the purge at 12:00 on
   shift 2. Inside: the todo (talk, Night Run), shift notes, `.pod3` (the
   maint account, "the password is Marrow's top score", podctl), `.history`.
   `cp` keeps copies past the purge.
3. **The maintenance account:** `su maint` / **709142** (Marrow's top score
   in Night Run, `/opt/games`). Opens everything: Marrow's and Hollis's
   homes, `/sys/pods`, the maint tools.
4. **Hollis's diary:** the word comes from **Ogre** (trust 2, alone in the
   hangar), asked about the lamp Hollis named; the hint is in Hollis's
   `units.txt` or Night Run's wrong way. `decrypt /home/ehollis/diary.enc
   lantern` → what the pods are, the wake sequence (`podctl wake` is refused
   for now: the wake ending is archived).

## The secrets (19)

`game/story/secrets.txt` (with the hints shown on the end screen).

| Secret | How |
| --- | --- |
| The ones before you | Read any former supervisor's file |
| Transferred | `cat /corp/memos/recent-transfer-okafor.txt` |
| Tinker, backwards | Tinker (trust 3, after asking about Okafor), "anything private?" |
| Okafor's account | `su dokafor` / `reknit` |
| Okafor's last note | As dokafor, `ls -a`, `.pod3` |
| Kept | `cp` one of Okafor's files before the purge |
| Night Run | `run nightrun` |
| The wrong way | Night Run: hold left into the NO ENTRY sign at the start of a run |
| The maintenance account | `su maint` / 709142 |
| The audit trail | maint: `auditctl list` |
| Silence | maint: `hqctl disable` |
| A deaf ear | Hauler (trust 2) has an "accident" with the uplink |
| The first voice | Ogre (alone in the hangar): the first supervisor |
| Hollis's diary | decrypt it with Ogre's word |
| What the pods are | read the diary |
| Pod 3 | maint: `podctl inspect 3` |
| Tinker's song | Tinker (trust 2, after asking about Okafor): pod 3 |
| What Hauler watches | Hauler: why it stands at the dock door at night |
| Estimated tenure | Recycle Bin, from shift 2: `.misdelivered` (hidden) |

## What costs time (and what corporate logs)

| Action | Facility time | Logged? |
| --- | --- | --- |
| Reading a file (first time) | 1 min per 5 lines, at least 5 (or its `minutes:` x3) | Former staff: +3 (files) |
| `grep` | 15 min | Matching former staff files: +2 |
| Talking to a unit | 3 min a line, 5 a reply | +1.5 a conversation (talk), **only if a camera sees the unit's room**; builds trust every 2 h |
| Replying to Pell | the same | No (what you say can be) |
| Ordering maintenance, sending a unit to a job or to inspect | Nothing up front: the time passes while it works (an errand) | No (but a conversation or an "accident" in a room a camera sees is) |
| Requisitions, priorities, answering requests, recharge / stand by | 5 min | No |
| Diagnose a unit | 30 min | No |
| Duties | 10-60 min | Undone at 14:00: standing down |
| Interim report (directive) | 20 min | No |
| A run of Night Run | 30 min | +3 first run each time it's opened (games) |
| `su dokafor` / `su maint` | 3 min | +6 / +10 (files / maint) |
| Root commands | 5 min | +4 to +15 (maint) |
| Activating a crated unit | 90 min | No |

Audits: hourly on duty, chance = (suspicion - 25)%. Suspicion fades 2 an hour.

## Clips to perform (the VR acting pass)

Story moments ask a unit to perform a clip by name; until it's recorded,
nothing happens. Record them in the recorder like any `act_*` clip.

| Clip | Unit | Moment |
| --- | --- | --- |
| `act_hum_pod3` | Tinker | Humming pod 3's rhythm (4 beats, pause, 3). Shift 2 08:40; the "song" conversation |
| `act_shocked_still` | Tinker | Told the truth about the pods: freezes, arms pulled in |
| `act_glitch_shiver` | Tinker | Rattled / unstable: jittery, twitchy |
| `act_look_at_camera` | Hauler | Turns its head up to the camera and holds. Shift 2 13:00; the "night" conversation |
| `act_lamp_to_camera` | Ogre | Swings the great eye slowly toward the camera |
| `act_lamp_dim` | Ogre | The lamp lowers, like a bow ("...lantern.") |
| `act_lamp_to_pods` | Ogre | The lamp sweeps toward the pod bay side and stops. Shift 3 13:45 |

| `act_wave_camera` | any | A unit that just repaired a camera: backs off and gives it a little wave |
| `idle_toss_wrench`, `idle_watch_door`, `idle_listen_pipes` | Hauler | Habits: tossing the wrench, watching the dock door, listening to the pipes |
| `idle_fiddle_radio`, `idle_hum_pod3`, `idle_look_up` | Tinker | Habits: the radio, humming at pod 3, looking up at Ogre |
| `idle_swing_crate`, `idle_sweep_lamp` | Ogre | Habits: swinging the crate across, sweeping the lamp around |

Worth adding for the new systems (not yet cued): a seize (a joint locking
mid-reach), a manual reboot (Tinker working at another unit's back panel),
Hauler's "accident" (a clumsy swing into the relay), unpacking a crate.

## Where it all lives

| File | What |
| --- | --- |
| `game/story/fs/` | The OS file system. `#!` headers: name, date, owner, learn, restricted, password, requires, gone_if, shift, minutes, exec, access (see `virtual_fs.gd`) |
| `game/story/shifts.txt` | Each shift's title and brief |
| `game/story/duties.txt` | Corporate's checklist per shift (shift 1's is the tutorial) |
| `game/story/events.txt` | Scripted moments per shift (corkHQ lines, robot lines, faults, seizes, directives, audits, clips) |
| `game/story/secrets.txt` | The secrets and their hints |
| `game/story/pods.txt` | Who's in the pods |
| `game/story/dialogue/*.txt` | Conversations: tinker, hauler, ogre, pell, new_unit |
| `game/corporate/hq_lines.txt` | corkHQ's lines, including Pell's escalation (`pell_<kind>_<level>`) |
| `game/corporate/catalog.txt` | What you can order (parts say what uses them) |
| `docs/archive/endings.txt` | The six endings, parked |
