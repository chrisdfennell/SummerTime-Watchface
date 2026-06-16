# Critter Feature — portable spec (for all seasonal watch faces)

"Critters" are little visitors that cross the screen once in a while. The engine
is **shared** across faces; only the creature set + palette is themed:

| Face            | Day visitors                          | Night visitors                |
|-----------------|---------------------------------------|-------------------------------|
| Bloom / Spring  | rabbit, songbird flock, butterfly     | hedgehog, fox, bat, owl       |
| Summertime      | crab, seagull (lands+walks), dolphin, whale | crab, dolphin, whale    |

This doc describes the **generic engine** (copy as-is) and the **per-face creature
set** (re-theme) so the feature can be dropped into the other faces cleanly.

Imported into Summertime on 2026-06-16 from `C:\programming\spring-watchface`
(`source/BloomView.mc`). The Summertime copy lives in `source/SummertimeView.mc`.

---

## 1. The generic engine (copy verbatim, it's face-independent)

### Timing / selection — `computeCritter(hour, min, sec, isNight)`
- Returns `[type, dir, frac, seed]` or `null`. At most ONE critter is ever active.
- `PERIOD = 38.0` s (a visitor may appear once per window), `CROSS = 8.0` s (how
  long one crossing lasts). `period % 5 == 0` windows are quiet (empty beach).
- `frac` = 0..1 progress across the screen; `dir` = +1 / -1 from a hash of
  `period`; `sel = (period*17+5) % 4` indexes a 4-entry day/night pool.
- Deterministic from the clock → no RNG, no state, identical each render within a
  second. (At 1 fps in high power a crossing is ~8 frames — intentionally subtle.)

### Crossing position (in the dispatcher `drawCritter`)
```monkeyc
var margin = (w * 0.18).toNumber();
var span = w + 2 * margin;
var x = (dir == 1) ? (-margin + frac * span).toNumber()
                   : (w + margin - frac * span).toNumber();
```

### Layering — draw each critter in the correct pass
A critter is drawn in a specific layer so it reads as "in" the scene. Bloom splits
sky vs ground; Summertime splits **water vs shore**:
- `isWaterCritter(type)` → drawn BETWEEN the back and front wave (water hides the
  splash base), so it looks like it breaches out of the sea.
- everything else → drawn AFTER the beach + palm (in front of the shore).
- Critters are ONLY drawn inside the active layer (`if (!mLowPower)`), never in
  AOD/low-power — so they never touch the partial-update budget.

### Outline technique (shared with the icons)
Draw a creature's silhouette helper 4× at ±1 diagonal offsets in black, then once
in color. Keeps it legible over a busy background.

### Sea-creature orientation — the shear helpers `crX` / `crY`
Sea creatures lean nose-up/down as they arc. Body space (bx = forward toward
travel dir, by = up) maps to screen with a vertical shear `tilt`:
```monkeyc
private function crX(x, dir, bx) { return (x + dir * bx).toNumber(); }            // horizontal = forward * dir
private function crY(y, bx, by, tilt) { return (y - by - tilt * bx).toNumber(); } // vertical, sheared by tilt*forward
```
`tilt = +k` ⇒ nose-up (forward end rises), `-k` ⇒ nose-down. Dolphin flips tilt at
the apex (`noseUp = frac < 0.5`); whale uses a fixed strong `tilt = 0.8`.

---

## 2. Summertime creature set (re-theme per face)

- **Crab** `CR_CRAB` (ground, day+night): domed shell + 3 scurrying legs/side +
  raised claws + eyestalks. Sits at `y = h*0.93`.
- **Seagull** `CR_SEAGULL` (day): phase-based crossing — glides down (`frac<0.35`),
  WALKS on the sand with stepping legs + folded wing (`0.35..0.65`), takes off
  (`>0.65`). One critter, three poses driven by `frac`.
- **Dolphin** `CR_DOLPHIN` (day+night): single smooth leap, `y = waterY -
  leapH*sin(frac*π)`, body/dorsal/fluke polygons via `crX`/`crY`.
- **Whale** `CR_WHALE` (day+night): big breach, `y = waterY - breachH*sin(frac*π)`,
  with pectoral flipper, belly grooves, eye, blowhole **spout**, and foam splash.

## 3. Settings wiring (every face)
- `resources/settings/properties.xml`: `<property id="ShowCritters" type="boolean">true</property>`
- `resources/settings/settings.xml`: a `boolean` setting referencing
  `@Strings.ShowCrittersTitle` / `@Strings.ShowCrittersPrompt`.
- `resources/strings/strings.xml`: those two strings (re-theme the prompt text).
- `loadSettings()`: read `ShowCritters` into `mShowCritters` (default true).
- `onUpdate`: `var crit = mShowCritters ? computeCritter(...) : null;` then the two
  layered draw calls.

---

## 4. Gotchas / lessons (read before porting)

- **No new code bugs were introduced or carried over in this import.** The Bloom
  critter code had no crashes to squash; the beach creatures are new code written
  to the same safe patterns (size floors via `if (s < N) { s = N; }`, fixed-size
  pools indexed by `% 4`, no unbounded loops, no per-frame allocations beyond the
  small polygon literals that only run during an ~8 s crossing).
- **Do NOT copy Bloom's cloud wrap** (`... % (w + 80) - 40`) — it has the negative-
  modulo bug that Summertime already fixed (see `watchface-fixes-log.md` #5). Only
  copy the critter functions, not surrounding scene code.
- **BUILD GOTCHA (environment):** the bash and PowerShell tools here share one
  working directory, so a `cd` into another project (e.g. spring-watchface) makes
  the next `./build.ps1` build the WRONG project. Always confirm the build line
  says `Output: bin\Summertime.prg` (not `bin\Bloom.prg`) before trusting a
  "BUILD SUCCESSFUL". Run `Set-Location C:\programming\summer-watchface` first.
- Critters animate at ~1 fps when awake (same as the rest of the scene) — this is
  expected, not a stutter bug.
