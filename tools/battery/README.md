# Battery measurement harness (Phase 0)

Companion to `docs/battery/` (ASSESSMENT.md + RECOMMENDATIONS.md). One session = one
scenario, ~10 minutes, on the Pixel, **unplugged**, over Wi-Fi adb. The session script
snapshots the ODPM power rails (per-rail energy: CPU, GPU, display, modem) and the app's
`[battery]` debug counter lines.

## One-time setup

### 1. Wi-Fi adb (required — a USB-tethered phone charges, which ruins the power numbers)

On the phone: **Settings → Developer options → Wireless debugging → ON**, then
**Pair device with pairing code**. With the code + pairing port shown on screen:

```powershell
adb pair <phone-ip>:<pairing-port>     # prompts for the 6-digit code
adb connect <phone-ip>:<port>          # the port on the main Wireless-debugging screen
adb devices                            # should list <phone-ip>:<port>  device
```

The pairing survives; after a reboot only `adb connect` is needed (the port changes —
check the Wireless debugging screen). Unplug USB after installing.

### 2. Build + install the PROFILE APK

The counters are compiled out of release builds; profile is AOT (near-release performance)
with the counters live.

```powershell
./build_android.ps1                    # once: engine .so → jniLibs (also makes a release APK)
cd app
flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```

**Baseline must be measured on the Phase 0 commit** (counters present, no fixes yet) —
`git log --oneline` should show `perf(battery): Phase 0 debug counters…` as the newest
commit when you build.

## Running a session

```powershell
cd tools/battery
./odpm_session.ps1 -Label idle-no-selection -Minutes 10
# add -Device 192.168.x.x:5555 if more than one device is connected
```

The script refuses to run while the phone is charging. Results land in
`tools/battery/results/<timestamp>-<label>/`: `power_before/after.txt` (ODPM rails),
`battery_before/after.txt`, `counters.txt` (the `[battery]` log lines), `session.txt`.

## The three baseline scenarios (~10 min each)

Same document for A and B — suggest 128×128, a few layers. Screen at a fixed medium
brightness, auto-brightness OFF, rotation locked, no other apps in the foreground,
notifications quiet. Start the scenario, start the script, then leave the phone alone.

| Label | Scenario | What to do |
|---|---|---|
| `idle-no-selection` | **A** | Editor open, Pencil selected, **no selection**, precision mode off. Draw one stroke, then hands off for the whole window. |
| `idle-with-selection` | **B** | Same document. Make a rectangular selection (ants visible), then hands off for the whole window. |
| `playback-2fps` | **D** | A small animation whose frames run at ~2 fps (e.g. 2 frames × 500 ms). Press Play, hands off; playback loops for the whole window. |

The A-vs-B delta isolates the marching-ants loop; A-vs-D isolates the playback ticker.
The `[battery]` `fps=` column is the direct code-level check (expect ~0 in A, ~60 in B
today, ~60 in D today regardless of animation fps).

## After the fixes

Re-run the same three sessions on the post-Phase-1 build (same document, same brightness)
and compare `power_before/after` rail deltas + the `fps=` column against the baseline.
Targets: RECOMMENDATIONS.md §Checkpoint 1.
