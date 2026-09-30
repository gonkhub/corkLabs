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

Both are placeholder primitives; final models will be rigid parts from Blender.
