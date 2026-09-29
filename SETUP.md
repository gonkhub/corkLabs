# corkLabs: Phase 1 setup

Goal: see both controllers as cubes in the headset, with live input readouts.

## One-time setup

1. **Godot 4.7.2**: download the standard Windows build (not .NET) from
   https://godotengine.org/download/windows and unzip it anywhere.
2. **Meta Horizon Link app** (already installed):
   - Settings → General → **OpenXR Runtime** → set Meta Horizon Link as active.
     (Done 2026-09-28. If Virtual Desktop takes it back after an update, set it again.)
   - Settings → General → turn on **Unknown Sources** so non-Store apps like
     Godot can run in the headset.
3. Plug the headset in with the USB cable, then in the headset open
   Quick Settings → **Link** and connect.

## Each session

1. Headset on Link first (you should see the Link home environment).
2. Open Godot 4.7.2 → Import → `Desktop/corkLabs/project.godot`.
3. Press **F5** (Run Project), then put the headset on.

## Phase 1 is done when

- [ ] You stand on an orange floor mark in a grey room.
- [ ] Each controller shows as a cube that follows your hand.
- [ ] Labels over each cube show trigger and grip moving smoothly 0.00–1.00.
- [ ] The stick values and A/B/X/Y/menu buttons react.
- [ ] Squeezing a trigger turns its cube orange.
- [ ] The text in front of you shows your head height (roughly your eye height).

## Phase 2: recorder

F5 now opens the recorder (`recorder/recorder.tscn`). The Phase 1 test scene
is still at `recorder/hello_vr.tscn` (open it and press F6 to run it).

| Control | Does |
| --- | --- |
| Left **MENU** button | 3-2-1 countdown (beeps), then record. Press again to stop and save. Press during the countdown to cancel |
| Right **A** | Replay the ghost from the start |
| Right **B** | Move the ghost: where you stood <-> 2 m in front, facing you |
| **Space** (keyboard) | Same as MENU |

Takes save to `takes/take_<date>T<time>.res`. Keep this folder: takes are the
source of truth, and robots get re-baked from them later. The newest take
loads automatically each time the recorder starts.

Self-test without a headset (checks save/load/playback):
`Godot --headless --xr-mode off --path . --script res://tests/test_take_roundtrip.gd`

### Phase 2 is done when

- [ ] Recording a ~30 s take (wave, point, squeeze triggers) saves without errors.
- [ ] The cyan ghost replays head and hands matching what you did, stepping aside
      to watch it "in place".
- [ ] Ghost cubes turn orange when the recorded trigger was squeezed.
- [ ] After stopping the game and pressing F5 again, the same take replays.
- [ ] The HUD shows roughly 72–120 Hz (whatever refresh rate Link is set to).

## If something's wrong

| Symptom | Fix |
| --- | --- |
| Monitor window says "OpenXR failed to start" | Link isn't connected, or Link isn't the active OpenXR runtime (step 2 above) |
| Game runs on the monitor but the headset shows Link home | Stop the game, check Unknown Sources is on, and run again |
| Cubes frozen / "(not tracked)" | Wake the controllers (press a button) and keep them in front of the headset |
| Stick or buttons read nothing | Open Project → Project Settings → XR → Action Map and check Godot created the default map |
