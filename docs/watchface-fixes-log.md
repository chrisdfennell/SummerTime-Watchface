# Watch Face Fix Log — Freeze / Performance / Z-Order

A running, portable record of bugs found and fixed across the watch faces, so the
same fixes can be applied to sibling projects (e.g. spring-watchface). Most of
these are **generic Connect IQ / Monkey C watch-face issues**, not specific to
Summertime — the "Portable?" flag on each entry says whether it likely applies
to your other faces too.

> Convention: file/line references point at `source/SummertimeView.mc` as of the
> fix. In your other faces the method names are probably the same (`onUpdate`,
> `onPartialUpdate`, `drawTextWithOutline`, `getSkyColors`, `normDeg`/`normHour`,
> `drawWave`), so search by method name rather than line number.

---

## 2026-06-16 — Freeze sweep + seconds marker z-order

Branch: `fix/freeze-and-seconds-zorder`. Verified with `./build.ps1 -Device fenix847mm` → BUILD SUCCESSFUL.

### Symptom
Face "keeps freezing" on the watch, and the orbiting "tiny sun" (citrus slice)
seconds marker was being drawn *behind* the bottom text.

### Root-cause summary
On Garmin, a watch face "freezes" almost always because a render path exceeds the
execution-time / power **budget** (especially `onPartialUpdate` in always-on mode)
or because of an actual infinite loop. The biggest offender here was
`onPartialUpdate` doing a full-screen clear + re-render every minute.

---

### Fix #1 — `onPartialUpdate` must be cheap (THE freeze fix)  ⭐ Portable: YES

**Problem.** `onPartialUpdate` (called up to once/second in always-on/sleep) was
calling the full `onUpdate(dc)`, which does `dc.clear()` over the whole screen and
re-renders the entire layout. `onPartialUpdate` runs under a strict budget;
blowing it repeatedly makes the system disable partial updates → the face appears
frozen in always-on.

**Before:**
```monkeyc
function onPartialUpdate(dc as Dc) as Void {
    var min = System.getClockTime().min;
    if (min == mLastMin) { return; }
    mLastMin = min;
    onUpdate(dc);            // full-screen clear + full re-render — budget killer
}
```

**After (key ideas):**
- Keep the per-minute throttle (`mLastMin`).
- Set a **clip region** to just the central time/date band, so `clear()` and the
  redraw are bounded to a small rectangle instead of the whole display.
- Redraw only what changes sub-minute. The always-on layer shows no seconds, so
  that's just time + date.
- Re-apply the same anti-burn-in pixel shift the full redraw uses.

```monkeyc
function onPartialUpdate(dc as Dc) as Void {
    var min = System.getClockTime().min;
    if (min == mLastMin) { return; }
    mLastMin = min;

    mLowPower = true;

    var dx = 0; var dy = 0;
    var settings = System.getDeviceSettings();
    var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
    if (hasBurnIn && mIsSleep) {
        var shift = computeBurnInShift();
        dx = shift[0]; dy = shift[1];
    }
    var cx = mCenterX + dx;
    var cy = mCenterY + dy;

    var clipY = (mHeight * 0.30).toNumber();
    var clipH = (mHeight * 0.34).toNumber();
    if (dc has :setClip) { dc.setClip(0, clipY, mWidth, clipH); }

    dc.setColor(BG_COLOR, BG_COLOR);
    dc.clear();
    drawTime(dc, cx, cy - (mHeight * 0.05).toNumber());
    if (mShowDate) { drawDate(dc, cx, cy + (mHeight * 0.06).toNumber()); }

    if (dc has :clearClip) { dc.clearClip(); }
}
```

**How to port:** Find any `onPartialUpdate` that calls `onUpdate` (or otherwise
clears/redraws the whole screen). Clip to only the region that actually changes
each second (the time, or the seconds indicator) and redraw just that. Adjust the
clip band to wherever your time sits.

---

### Fix #2 / #3 — Cut per-frame cost & heap allocations  ⭐ Portable: YES

`onUpdate` allocated several arrays *every frame*, which churns Garmin's tiny heap
and triggers frequent GC (visible as stutter/jank). Hoisting them to constants /
reusable buffers is a free win with zero visual change.

1. **Star field arrays** — were two 18-element literals rebuilt every night frame.
   Hoisted to `private const STAR_X` / `STAR_Y`.

2. **Sky gradient keyframes** — `getSkyColors` rebuilt three 9-element arrays per
   frame, and the two color tables were *identical* in both the real-sun and
   fallback branches. Hoisted the color tables to `private const SKY_TOP` /
   `SKY_BOTTOM`, and the fallback hours to `SKY_HOURS_FALLBACK`. Only the dynamic
   real-sun `hours` array is still built per frame.

3. **Wave polygon buffer** — `drawWave` did `new [steps+3]` plus 15 `[x,y]` pair
   allocations on every call (×2 waves/frame). Now reuses a persistent
   `mWavePts` buffer and mutates the point pairs in place:
```monkeyc
if (mWavePts == null) {
    var buf = new [steps + 3] as Array<Array>;
    for (var k = 0; k < steps + 3; k++) { buf[k] = [0, 0]; }
    mWavePts = buf;
}
var points = mWavePts;
points[0][0] = w; points[0][1] = h;   // mutate, don't reallocate
// ...
```

4. **Dedupe burn-in offset** into `computeBurnInShift()` so `onUpdate` and
   `onPartialUpdate` share one implementation.

**How to port:** Search your `onUpdate`/draw helpers for array literals (`[ ... ]`)
and `new [ ... ]` inside the per-frame path. Anything constant → hoist to a
`private const`. Anything rebuilt with the same size each frame → reuse a member
buffer.

---

### Fix #4 — Infinite-loop guard in `normDeg` / `normHour`  ⭐ Portable: YES (if you have sun math)

**Problem.** These normalize angles/hours with `while` loops:
```monkeyc
while (a >= 360.0) { a -= 360.0; }   // NaN/Infinity here = infinite loop = hard freeze
```
If the sunrise/sunset trig ever produced a non-finite value, the subtract-in-a-loop
would spin forever and hang the face. (Not currently reachable, but one math edge
case away.)

**After** — bounded modulo + a non-finite guard, which can never loop:
```monkeyc
private function normDeg(a as Float) as Float {
    if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
    var r = a - 360.0 * Math.floor(a / 360.0);
    if (r < 0.0) { r += 360.0; }
    if (r >= 360.0) { r -= 360.0; }
    return r;
}
```
(Same pattern for `normHour` with `24.0`.)

**How to port:** Replace any `while (x >= N) { x -= N; }` / `while (x < 0) { x += N; }`
normalizers with the modulo form above. This is a general rule: never normalize a
float with an unbounded `while` loop in a render path.

---

### Fix #5 — Negative-modulo cloud wrap  Portable: MAYBE (any `%`-based animation)

**Problem.** Monkey C's `%` keeps the sign of the dividend, so a drifting position
that goes negative wraps off-screen:
```monkeyc
var cx2 = ((w * 0.7 - (cloudOffset * 0.05)).toNumber()) % (w + 80) - 40;  // can go negative
```

**After** — positive modulo:
```monkeyc
var span = w + 80;
var cx2 = (((((w * 0.7 - (cloudOffset * 0.05)).toNumber()) % span) + span) % span) - 40;
```

**How to port:** Any `value % span` where `value` can be negative should be
`((value % span) + span) % span`.

---

### Z-order — seconds marker above everything  Portable: pattern only

The orbiting "tiny sun" (citrus slice) seconds marker was drawn inside the
background/active layer (section "I"), *before* the time, date, complications and
steps bar — so the bottom text covered it.

**Fix:** Move the marker's draw call to the very END of `onUpdate`, after all
text/complications, still guarded by `if (!mLowPower)`. Draw order = z-order in
CIQ: last drawn = on top.

**How to port:** Whatever element must sit on top (seconds hand/marker, an alert
dot, etc.) should be the last thing drawn in `onUpdate`.

---

### Fix #6 — Cache `System.getDeviceSettings()` per frame  Portable: YES

**Problem.** `System.getDeviceSettings()` was called up to three times per redraw
(`onUpdate` for burn-in, `drawTime` for `is24Hour`, `getWeatherString` for
`temperatureUnits`). Each call allocates a fresh settings object.

**After.** Cache it once at the top of the redraw in an instance field and reuse:
```monkeyc
private var mSettings as System.DeviceSettings or Null = null;

// in onUpdate() and onPartialUpdate():
var settings = System.getDeviceSettings();
mSettings = settings;   // cache for drawTime / getWeatherString this frame

// in drawTime() / getWeatherString():
var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
```

**How to port:** Same pattern for any value read from `getDeviceSettings()` (or
`getActivityInfo()`, etc.) in more than one place per frame — read once, cache,
reuse. Keep the `!= null` fallback so helpers are safe if called outside a redraw.

---

### Fix #7 — Throttle sunrise/sunset retries  Portable: YES (if you compute sun times)

**Problem.** `updateSunTimes` only caches the result once it is *valid for the
day*. Until then (no location fix yet, or a degenerate `sunset <= sunrise`
result) it re-ran the location lookup **and** the heavy NOAA trig on every redraw.

**After.** Throttle retries to once per 60 s while not-yet-valid, and reset the
timer on a new day so the first frame of the day retries immediately:
```monkeyc
private var mSunLastTry as Number = -10000;  // epoch sec of last retry

// inside updateSunTimes(), after the new-day reset (which also sets
// mSunLastTry = -10000):
var nowSec = Time.now().value();
if ((nowSec - mSunLastTry) < 60) { return; }
mSunLastTry = nowSec;
// ... then getLocationDeg() + computeSunEvent() as before
```

**How to port:** Any "compute until success, then cache" routine in the render
path should throttle its failed attempts (a `lastTry` timestamp) instead of
retrying every frame. Reset the throttle when the cache key changes (here, the day).

---

### Fix #8 — `onPartialUpdate` cheap-path must be gated to AMOLED always-on  ⭐ Portable: YES

**Regression introduced by Fix #1, caught on a second pass.** The clipped
"clear a band + redraw time/date" path is only correct when the sleep frame is
the dim always-on layer (AMOLED, `requiresBurnInProtection == true`). On **MIP**
devices the sleep frame is the *full colour scene*, and MIP devices also call
`onPartialUpdate` — so the clipped clear painted a **black rectangle across the
middle of the scene** every minute.

**Fix:** gate the cheap path; otherwise fall back to the original full redraw.
```monkeyc
var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
var aod = hasBurnIn && mIsSleep;
if (!aod || !(dc has :setClip)) {   // MIP / no-clip: keep original behaviour
    onUpdate(dc);
    return;
}
// ... AMOLED always-on: clipped time/date redraw ...
```

**How to port:** Any "lightweight clipped partial update" optimization must check
`requiresBurnInProtection` first. MIP and AMOLED have opposite sleep-frame
contents, so a single partial-update path can't serve both.

---

### Fix #9 — Cache the AMOLED sky gradient in a `BufferedBitmap`  ⭐ Portable: YES (AMOLED faces)

**Problem.** When awake, `onUpdate` runs ~once/second and the AMOLED gradient
re-ran its ~86-row `fillRectangle`+`lerpColor` loop every frame — even though the
gradient colors depend only on hour+minute, so they're identical for a whole
minute.

**Fix.** Render the gradient into a buffered bitmap once and blit it; only
re-render when the colors or dimensions change (or the graphics pool reclaims it).
MIP is untouched (it uses a single flat fill, not the gradient).
```monkeyc
private var mSkyBufRef as Graphics.BufferedBitmapReference or Null = null;
private var mSkyKeyTop as Number = -1; // + mSkyKeyBottom / mSkyKeyW / mSkyKeyH

private function getSkyBitmap(w, skyH, cTop, cBottom) as Graphics.BufferedBitmap or Null {
    if (!(Graphics has :createBufferedBitmap)) { return null; }   // caller renders directly
    var bmp = (mSkyBufRef != null) ? mSkyBufRef.get() : null;     // null if pool reclaimed it
    if (bmp != null && cTop == mSkyKeyTop && cBottom == mSkyKeyBottom
            && w == mSkyKeyW && skyH == mSkyKeyH) { return bmp; }  // cache hit
    try {
        var ref = Graphics.createBufferedBitmap({ :width => w, :height => skyH });
        if (ref == null) { return null; }
        mSkyBufRef = ref;
        bmp = ref.get();
        if (bmp == null) { return null; }
        var bdc = bmp.getDc();
        // ... the per-row gradient fill loop, into bdc ...
        mSkyKeyTop = cTop; mSkyKeyBottom = cBottom; mSkyKeyW = w; mSkyKeyH = skyH;
        return bmp;
    } catch (e) { mSkyBufRef = null; return null; }
}
```
Caller: `var b = getSkyBitmap(...); if (b != null) { dc.drawBitmap(0,0,b); } else { /* direct */ }`.

**Gotchas / how to port:**
- **Memory.** A full-width × 0.76-height buffer is large; only do this on the
  AMOLED path (those devices have the bigger graphics pool). Always `try/catch`
  the allocation and fall back to direct rendering so a low-memory device still
  works.
- **Pool reclamation.** `BufferedBitmapReference.get()` can return `null` at any
  time — always null-check and re-render, don't cache the bitmap object directly.
- Key the cache on whatever the buffer's contents depend on. Here colors change
  only with hour+minute, so the fill loop runs ~once/minute instead of ~60×.

---

### Fix #10 — Cache duplicate per-frame syscalls  Portable: YES

`System.getClockTime()` (×3) and `ActivityMonitor.getInfo()` (×3) were each called
several times per redraw. Cache once at the top of `onUpdate`/`onPartialUpdate`
into instance fields (`mClock`, `mActInfo`) and read those everywhere, with a
`!= null` fallback for safety — same pattern as the device-settings cache (#6).

---

### Fix #11 — Skip the weather lookup in always-on  Portable: YES

`drawDate` called `getWeatherString()` (→ `Weather.getCurrentConditions()`) even in
always-on. Now gated on `mLowPower`:
```monkeyc
var weatherStr = mLowPower ? null : getWeatherString();
```
This keeps the weather lookup out of the partial-update budget **and** makes the
dim AOD date identical between the full and partial redraws (no flicker).

---

## 2026-06-16 (later) — tactix 8 still froze "while actively looking"

Hardware report: on a real tactix 8 (AMOLED 454) the seconds marker **stopped
moving while actively looking** (not the normal always-on transition). That means
the per-second high-power `onUpdate` was too heavy for the device's update budget,
so the OS stopped issuing per-second updates. The simulator does NOT enforce this
timing, so it looked fine there. Two fixes — and crucially, **the scene keeps
animating** (the per-minute "bake the whole scene" idea was rejected on purpose).

### Fix #12 — `BufferedBitmap` leak: allocate once, repaint in place  ⭐ Portable: YES

**Regression from Fix #9.** `getSkyBitmap` called `Graphics.createBufferedBitmap`
**every minute** (whenever the gradient colors changed). On real hardware that
churns the graphics pool; once it's exhausted, `createBufferedBitmap` starts
failing, we fall into the slow per-frame 86-fill fallback **forever**, and the
face bogs down / freezes the longer you wear it.

**Fix:** allocate the buffer ONCE (re-allocate only if the pool reclaimed it or
the size changed), and just repaint the gradient into the *existing* buffer when
the colors change:
```monkeyc
var bmp = (mSkyBufRef != null) ? mSkyBufRef.get() : null;
if (bmp == null || w != mSkyKeyW || skyH != mSkyKeyH) {   // allocate ONCE
    var ref = Graphics.createBufferedBitmap({ :width => w, :height => skyH });
    ... mSkyBufRef = ref; bmp = ref.get(); ...
    mSkyKeyTop = cTop + 1;   // invalidate so it repaints below
}
if (cTop != mSkyKeyTop || cBottom != mSkyKeyBottom) {     // repaint IN PLACE
    var bdc = bmp.getDc(); /* gradient fill loop */ ...
}
```
**Lesson (general):** never call `createBufferedBitmap` on a hot path keyed on a
value that changes — allocate once, reuse `getDc()`. Recreating = pool churn = OOM.

### Fix #13 — Adaptive render quality (self-tuning to the device)  ⭐ Portable: YES

Instead of hardcoding detail cuts (and guessing per device), `onUpdate` measures
its own render time with `System.getTimer()` and nudges an `mQuality` level
(0..3) up/down with hysteresis. Expensive detail scales with it, so the scene
**keeps fully animating** and only sheds detail on hardware that can't keep up —
and it auto-fits a tactix 8 vs a tiny FR165 with no per-device guessing.

```monkeyc
private var mQuality as Number = 2;       // 3 = full detail, 0 = leanest
private var mFrameStart as Number = 0;
private const Q_SLOW_MS = 220;            // frame slower than this -> drop a level
private const Q_FAST_MS = 120;            // faster than this -> raise a level

// top of onUpdate:
mFrameStart = System.getTimer();
// end of onUpdate (active frames only):
var dt = System.getTimer() - mFrameStart;
if (dt > Q_SLOW_MS) { if (mQuality > 0) { mQuality--; } }
else if (dt < Q_FAST_MS) { if (mQuality < 3) { mQuality++; } }
```

Knobs that read `mQuality` (tune per face):
| Knob | q3 | q2 | q1 | q0 |
|---|---|---|---|---|
| `drawTextWithOutline` passes | 8 | 4 | 2 | 0 |
| Palm trunk segments | 12 | 10 | 8 | 8 |
| Palm leaf (frond) segments | 7 | 6 | 5 | 4 |
| Sun rays | on | on | off | off |

**How to port:** add the three fields + the timer at the top and the hysteresis
at the bottom of `onUpdate` (active branch only — don't adapt in low-power/AOD).
Then make each face's most expensive per-frame draws read `mQuality`. Pick the
knobs by what's heavy in that face (here: the long outlined date text and the
~100-line palm). Thresholds (220/120 ms) are starting points — tune to taste.

**Why both:** #12 removes a real leak that forces the slow path; #13 guarantees
that whatever the device's true budget is, the face throttles detail (not the
animation) to stay under it. Together they target "freezes while actively looking"
without flattening the living scene. NOTE: verified to build (AMOLED + MIP) and
run in the simulator, but the simulator can't reproduce the hardware update-budget
throttle — real-device confirmation is required.

---

## Notes / general rules
- **"Is it the freeze?"** — audit, in order: anything in `onPartialUpdate`
  (must be cheap + clipped), any `while` loop fed by float math (NaN/Inf = hang),
  any per-frame allocation, and any expensive call (settings/clock/activity/sun
  trig/sensor reads) that isn't cached or throttled.
- **Left intentionally unchanged (verified safe):** the sun-math trig saturates
  rather than producing NaN/Inf, and the sky/arc divisions can't hit zero given
  the guarded ranges. The `drawTextWithOutline` 8-pass outline was kept as-is to
  avoid a visual change; drop it to 4 passes only if text cost ever matters.
- **Adaptive quality (#13) is the general answer to "too heavy on device X":**
  measure the frame, scale detail, keep the animation. Prefer it over hardcoded
  per-device cuts.
- All thirteen fixes from 2026-06-16 are applied to Summertime and verified
  building for AMOLED (`fenix847mm`) and MIP (`fenix7`, `fr165`). Fixes #12/#13
  target a hardware-only freeze the simulator can't reproduce — confirm on a real
  tactix 8 before treating them as proven.
