# corkLabs: the story so far (SPOILERS)

Everything a player can find, how it's found, and where it lives, so it can
be reviewed, rewritten and rebalanced. First pass, 2026-09-30: all of it is
placeholder writing meant to be walked back or rewritten freely. Every piece
is a plain text file; no code changes needed to rewrite a line.

## The shape of a run

One continuous timeline of **three shifts** (Day 1-3, 06:00-14:00). Each
shift: a **brief** (what corporate wants, what happened overnight, today's
duties) → **clock in** → play (time only moves when you act) → **14:00: end
of shift** (review, standing, duties) → **clock out** (the night passes, the
facility runs without you) → next brief. After shift 3, an **ending**.

You can be **dismissed** at any point:

| How | What triggers it |
| --- | --- |
| Performance | Standing reaches 0 (bad reviews, undone duties, crashed units) |
| Misconduct | Two audits catch you (suspicion from violations; audits every hour on duty, a big one at 13:00 on shift 3) |
| Catastrophe | Coolant empty for 30 facility minutes, or throughput under 30% for an hour, on your watch |

Dismissed: **retry the shift** (from its brief checkpoint) or **start over**
on a new save. The **personnel file** (`user://supervisor_archive.json`)
remembers every run: shifts worked, dismissals, secrets ever found, endings
seen. It shows on the login screen and on the ending screen.

What carries between runs is **what the player remembers**: a new save still
accepts `su maint` and the password, `talk tinker`, `decrypt ... lantern`...
The game just doesn't list them in `help` until they're used again.

## Two ways to play (and everything between)

**The good supervisor**: do the Duties (reports, inspections, diagnostics,
reading the Code of Conduct, confirming the purge, preparing for the audit),
keep throughput up, don't open what you're told not to. Standing rises;
suspicion stays low. Endings: *Contract Renewed*, *Promoted* (standing 85+,
no warnings: you become a liaison yourself).

**The rascal**: read the former supervisors' files, talk to the units, play
the game, log in as maint, look in the pods. Every one of those is logged
(suspicion); the audit trail can be read and purged, the corkHQ link muted.
Endings: *Witness* (you know what's in the pods, and who), *Transferred*
(you know, and they know you know), *Awake* (you open pod 3).

## The cast

| Who | Where | What |
| --- | --- | --- |
| **You** | the terminal room (no door) | Supervisor #6, probationary |
| **Ms. Pell** | the corkHQ panel | Your liaison. "She is always in touch." Reply to her from the panel |
| **Edwin Hollis** | `/home/ehollis`, pod 2 | Founding supervisor 1979-1994. Built the units, "built the dark". Found the wake sequence. Transferred |
| **Ruth Marrow** | `/home/rmarrow`, pod 4 | 2003-2011. Made the maint account, wrote NIGHT RUN, talked to the units. Terminated, then transferred |
| **T. Vance** | `/home/tvance` | 2014, three days. "They are breathing." |
| **J. Kim** | `/home/jkim` | 2017, one shift. "the panel won't close" |
| **Dele Okafor** | `/home/dokafor` (purged at 12:00 on shift 2), pod 3 | 2019 until two days ago. Talked to Tinker every morning. Looked in pod 3. Asked to "come to the hangar for a conversation" |
| **Tinker** | everywhere on rails | Curious, lonely; a knowledge filter stops it knowing what the pods are |
| **Hauler** | everywhere on rails | Patient; watches Ogre's light at night |
| **Ogre** | the hangar ceiling | The oldest. No filter ("it already knows"). Keeps Hollis's word |

## The secrets (15) and how to find them

`game/story/secrets.txt` has the list (and the hints shown on the ending
screen for the ones not found).

| Secret | How |
| --- | --- |
| The ones before you | Read any file in a former supervisor's home (`cat /home/dokafor/todo.txt`). Each first read: suspicion +3 |
| Transferred | `cat /corp/memos/recent-transfer-okafor.txt` |
| Okafor's last note | `ls -a` in `/home/dokafor` shows `.pod3` (before the purge!) |
| Night Run | `run nightrun` (from `/opt/games`, mentioned in Okafor's todo and Marrow's README), or open it in Files |
| The wrong way | In Night Run, at the start of a run, **hold left** into the NO ENTRY sign until you slip through (1.6 s). Marrow's message: ask the one who never leaves about its light |
| The maintenance account | `su maint`, password **709142**: Marrow's top score in Night Run ("the password is the top score") |
| The audit trail | As maint: `auditctl list` |
| Silence | As maint: `hqctl mute <minutes>` |
| The first voice | `talk ogre` (only when no other unit is in the hangar), ask about the first supervisor |
| Hollis's diary | `decrypt /home/ehollis/diary.enc lantern`. The word: ask Ogre gently about the lamp Hollis named (needs the hint from Night Run's wrong way or `/home/ehollis/units.txt`) |
| What the pods are | Read the decrypted diary. Also teaches `podctl` and the wake sequence |
| Pod 3 | As maint: `podctl inspect 3`. It's Okafor. (Pod 2 is Hollis, pod 4 is Marrow) |
| Tinker's song | `talk tinker`, ask who was here before, then about pod 3 |
| What Hauler watches | `talk hauler`, ask why it stands at the dock door at night |
| Awake | As maint, having read the diary: `podctl wake 3`, then confirm. Ends the game |

Other things to find: `whoami`, `ls -l` (dates, owners), `/var/log/sessions.log`
(every supervisor's last session: TRANSFER), `/sys/units/*.cfg` (the
knowledge filters), `/corp/policy/conduct.txt` (every rule is a hint of what
exists), `exit` when you're not maint ("There is no door.").

## The Terminal as a thing you learn

A new supervisor's `help` lists: help, status, clear, ls, cd, cat, pwd.
Reading `~/welcome.txt` adds the job commands (units, jobs, order, priority,
plant, log, open, duties). Typing any real command teaches it ("new command
noted"). `help` ends with "There are more. There are always more." while
there are. Maintenance commands are real but answer "permission denied"
until you're maint. `sound` is a dev tool: it works but never shows in help.

## What costs time (and what corporate logs)

| Action | Facility time | Logged as a violation? |
| --- | --- | --- |
| Reading a file (first time) | 1 min per 15 lines, or its `minutes:` | Former staff files: +3 each (Night Run folder +2) |
| Talking to a unit | 1 min a line, 2 min a reply | +1.5 per conversation (conduct rule 2); steadies the unit |
| Replying to Pell | same | No, but what you say can be |
| Duties | their minutes (5-30) | No: standing up when done, down when not |
| Orders, priorities, requisitions, maintenance requests, spare parts | 2 min | No |
| Inspect a device, Diagnose a unit | 10 min | No |
| A run of Night Run | 10 min | +3 the first run each time it's opened |
| `su maint` | 1 min | +10 (+3 for a wrong password) |
| Root commands | 2 min | +4 to +15; forced installs can be caught on the spot (35%) |
| Clock in / the night | to 06:00 / to 05:55 next day | No |

Audits: every facility hour on duty, chance = (suspicion - 25) %. A muted
corkHQ link at audit time is itself logged (+12). Suspicion fades 2 an hour.

## Clips to perform (the VR acting pass)

Story moments ask a unit to perform a clip by name. Until it's recorded,
nothing happens (the robot keeps doing what it was doing), so these can be
performed in any order. Record them in the recorder like any `act_*` clip,
name them exactly this, and they play.

| Clip | Unit | Moment |
| --- | --- | --- |
| `act_hum_pod3` | Tinker | Humming pod 3's rhythm (4 beats, pause, 3) at the pod row. Shift 2 08:40; the "song" conversation |
| `act_shocked_still` | Tinker | Told the truth about the pods: freezes, arms pulled in, a slow look around |
| `act_glitch_shiver` | Tinker | Rattled / unstable: jittery, twitchy, arms not quite under control |
| `act_look_at_camera` | Hauler | Turns its head up to the camera and holds. Shift 2 13:00; the "night" conversation |
| `act_lamp_to_camera` | Ogre | Swings the great eye slowly toward the camera (remembering Hollis) |
| `act_lamp_dim` | Ogre | The eye/lamp lowers, like a bow ("...lantern.") |
| `act_lamp_to_pods` | Ogre | The lamp sweeps slowly toward the pod bay side and stops. Shift 3 13:45 |

Add more with `perform | robot | clip` in `events.txt`, or `~ perform clip`
in a conversation.

## Where it all lives

| File | What |
| --- | --- |
| `game/story/fs/` | The OS file system: one .txt per file, folders are folders. `#!` headers: name, date, owner, learn, restricted, password, requires, gone_if, shift, minutes, exec (see `virtual_fs.gd`) |
| `game/story/shifts.txt` | Each shift's title and brief |
| `game/story/duties.txt` | Corporate's checklist per shift |
| `game/story/events.txt` | Scripted moments per shift (corkHQ lines, robot lines, faults, audits, clips) |
| `game/story/endings.txt` | Endings, first match wins |
| `game/story/secrets.txt` | The secrets and their hints |
| `game/story/pods.txt` | Who's in the pods (maintenance view) |
| `game/story/dialogue/*.txt` | Conversations: tinker, hauler, ogre, pell |
| `game/corporate/hq_lines.txt` | corkHQ's regular lines (reviews, nags) |
