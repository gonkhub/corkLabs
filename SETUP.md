# corkLabs: headset setup

How to get the Quest 3 talking to Godot. For everything else (controls,
workflow, tools), see [README.md](README.md).

## One-time setup

1. **Godot**: the project currently uses Godot **4.3** (on your Desktop). A later
   move to 4.6+ is planned for Godot's new IK modifiers.
2. **Meta Horizon Link app**:
   - Settings → General → **OpenXR Runtime** → set Meta Horizon Link as active.
     (Done 2026-09-28. If Virtual Desktop takes it back after an update, set it again.)
   - Settings → General → turn on **Unknown Sources** so non-Store apps like
     Godot can run in the headset.
3. Plug the headset in with the USB cable, then in the headset open
   Quick Settings → **Link** and connect.

## Each session

1. Headset on Link first (you should see the Link home environment).
2. Open the project in Godot. The first time after an update, the **Takes**
   panel appears next to Scene/Import (top-left).
3. Open `recorder/recorder.tscn` and press **F6** (runs the recorder; F5 now runs the game), then put the headset on.

## Checklists

**Phase 1 (done 2026-09-28):** cubes follow your hands, inputs read 0.00–1.00.
Run `recorder/hello_vr.tscn` with F6 to repeat it.

**Recorder, first time in VR:**

- [ ] A robot (Hauler) hangs in front of you and mirrors you live.
- [ ] Left X switches to Tinker, then "cubes only", then back.
- [ ] Record ~20 s: countdown beeps, HUD shows `[REC]`, stopping saves and bakes.
- [ ] The robot replays the take; Right A switches back to live.
- [ ] Trigger closes claws, sticks move the eye/lid, A/X blinks, B/Y flashes.
- [ ] Left Y + record: the previous take plays on a second robot to your right.
- [ ] Left stick click → punch-in RIGHT: only your right arm is live, the rest replays.

## If something's wrong

| Symptom | Fix |
| --- | --- |
| Monitor says "OpenXR did not initialize" | Link isn't connected, or Link isn't the active OpenXR runtime (step 2 above) |
| Game runs on the monitor but the headset shows Link home | Stop the game, check Unknown Sources is on, and run again |
| Cubes/robot frozen or "(not tracked)" | Wake the controllers (press a button) and keep them in front of the headset |
| Stick or buttons read nothing | Project → Project Settings → XR → Action Map: check the default map exists |
| No beeps in the headset | Windows is sending sound to the PC speakers; set the Oculus audio device as default, or turn on audio mirroring in the Link app |
| No **Takes** panel in the editor | Project → Project Settings → Plugins: enable "corkLabs Pipeline" |
