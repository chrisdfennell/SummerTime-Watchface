# Summertime Watch Face
 
A premium, golden-hour beach themed **digital watch face** for **Garmin** watches, written in Monkey C for Connect IQ. Originally built for the **Fenix 8 / tactix 8**, it now runs on every Connect IQ 4.0+ round watch (see [Hardware / scaling](#hardware--scaling)).

Summertime brings a warm, relaxing, and beautiful tropical beach aesthetic to your watch:
 
- **Living Sky Procedural Backdrop**: A smooth color gradient shifting through sunrise pastels, midday azure, sunset marigold, and a starry deep night backdrop.
- **Arcing Celestial Objects**: A glowing sun (with rotating rays and procedural bloom) and a crescent silver moon rise and set along a circular path, driven by the **real sunrise/sunset** computed from the watch's location and today's date (falls back to a fixed summer schedule when no location fix is available). The sky, day/night, and stars all follow the same real sun times.
- **Drifting Clouds & Rolling Waves**: Fluffy clouds drift across the sky, and overlapping wave layers roll gently at the bottom with real-time wave physics in active mode.
- **Swaying Palm Silhouette**: A segmented palm trunk and wind-swept fronds sway in the breeze at the shoreline.
- **Citrus Slice Seconds**: A floating orange slice second indicator (with a dark rind border for legibility) orbits the outer perimeter.
- **Centered Digital Time**: Large, clean, rounded clock numerals (Arial Rounded MT Bold) centered with high-contrast black outlining.
- **Centered Date & Weather**: An elegant date line (Segoe UI Light) showing the calendar date and dynamic weather temperature (with automatic Celsius/Fahrenheit unit conversion).
- **Configurable Complications**: The bottom-left and bottom-right complications are each chosen in the app settings, and the watch draws a matching icon:
  - **❤ Heart Rate** (coral heart) — live BPM, sampled at most once every ~10s to spare the battery.
  - **⚡ Body Battery** (gold bolt) — Garmin's 0–100 energy score.
  - **🔋 Device Battery** (turquoise battery with a live fill bar) — the watch's charge.
  - **👣 Steps** (sandy shoe) — today's step count.
  - **🔥 Calories** (sunset flame) — today's calories.
  - **Off** — hide the complication.
  - Defaults: left = Heart Rate, right = Device Battery.
  - **Bottom-center**: A steps progress bar (sand/gold themed) + steps numeric count, always shown.
- **High-Contrast Text Outlines**: All text elements (clock, date, and metrics) are drawn with a custom black outline to ensure legibility against any dynamic gradient or wave background.

## Hardware / scaling

Originally built for the tactix 8 / Fenix 8, Summertime now targets **every Connect IQ 4.0+ round watch that supports watch faces**. The full product list lives in [manifest.xml](manifest.xml); the families covered are:

- **Forerunner** — 165, 255 (incl. S/Music), 265 / 265S, 570, 955, **965**, **970**
- **fenix / epix / enduro** — fenix 7 (S/X, Pro), fenix 8 (AMOLED + Solar), fenix E, epix 2 / Pro (42/47/51mm), enduro 3
- **Venu / Vivoactive** — Venu 2 / 2S / 2 Plus, Venu 3 / 3S, Venu 4 (41/45mm), Vivoactive 5 / 6
- **Instinct** — Instinct 3 (AMOLED 45/50mm, Solar 45mm), Instinct E (40/45mm), Instinct Crossover (AMOLED)
- **Specialty** — Approach S50 / S70 (golf), Descent G2 / Mk3 (dive), D2 Air X10 / Mach 1 / Mach 2 (aviation), MARQ 2 / Aviator

Edge bike computers and handheld GPS units are excluded (not watches), and the **square/rectangular panels (Venu Sq 2, Venu X1) are excluded too** — the circular layout is designed for round screens.

### How it scales

Everything is laid out in percentages of `dc.getWidth()/getHeight()` and the screen center, so the same source renders across every panel. Because bitmap fonts don't scale, [tools/gen_fonts.py](tools/gen_fonts.py) bakes a correctly-sized font set for each distinct resolution and [monkey.jungle](monkey.jungle) maps every product to the right one:

| Resolution | Set                          | Example devices |
|------------|------------------------------|-----------------|
| 454×454    | `resources/` (base)          | Fenix 8 47/51mm, FR965/970, Venu 3, epix 2 Pro 51mm |
| 416×416    | `resources-round-416x416/`   | Fenix 8 43mm, FR265, epix 2, Venu 2 |
| 390×390    | `resources-round-390x390/`   | FR165, Venu 3S, Vivoactive 5/6, Instinct 3 AMOLED 45mm |
| 360×360    | `resources-round-360x360/`   | FR265S, Venu 2S |
| 280×280    | `resources-round-280x280/`   | Fenix 7X, Fenix 8 Solar 51mm, enduro 3 |
| 260×260    | `resources-round-260x260/`   | FR255/955, Fenix 7, Fenix 8 Solar 47mm |
| 240×240    | `resources-round-240x240/`   | Fenix 7S |
| 218×218    | `resources-round-218x218/`   | FR255S |
| 176×176    | `resources-round-176x176/`   | Instinct 3 Solar 45mm, Instinct E 45mm |
| 166×166    | `resources-round-166x166/`   | Instinct E 40mm |

Re-run `python tools/gen_fonts.py` after changing font sizes or adding a new resolution. Fonts scale by `min(width, height)` so they fit the shorter axis on rectangular panels.

## Always-on display

The face has two render paths sharing one `onUpdate()`:

- **Active mode** — full brightness, animations (waves, swaying palm, sun rotation, drifting clouds), sky gradients, and text outlines.
- **Always-on / low-power** (`mIsSleep`) — burn-in-safe: dim grey time/date, thin outline representations of the battery metrics, steps progress outline, and **no visual fills or background animations**. All lit pixels are shifted a few pixels each minute (`requiresBurnInProtection`). `onPartialUpdate()` only repaints when the minute changes, staying well inside the always-on power budget.

## Data sources

- **Steps + goal + calories:** `ActivityMonitor.getInfo()` (`steps`, `stepGoal`, `calories`).
- **Heart rate:** `Activity.getActivityInfo().currentHeartRate`, falling back to `ActivityMonitor.getHeartRateHistory()`; cached and sampled at most once every ~10s.
- **Device battery:** `System.getSystemStats().battery`.
- **Body Battery:** `SensorHistory.getBodyBatteryHistory()`. Fails gracefully if the value is unavailable.
- **Sunrise/sunset:** computed (NOAA almanac) from the last-known location (`Activity.getActivityInfo().currentLocation`, then `Weather.getCurrentConditions().observationLocationPosition`) — neither powers the GPS. Falls back to a fixed summer schedule with no fix.
- **Weather:** `Weather.getCurrentConditions()` (uses Connect IQ weather APIs to display current temperature in Celsius or Fahrenheit depending on device settings).

## Settings

Editable in Garmin Connect / the simulator's App Settings:

- **Show Date** — toggle the date and weather line.
- **Step Goal Override** — steps for a full shoreline bar; `0` uses the watch's own step goal.
- **Bottom-Left Complication** / **Bottom-Right Complication** — choose Heart Rate, Body Battery, Device Battery, Steps, Calories, or Off for each. Defaults: left = Heart Rate, right = Device Battery.

## Build & run

Prerequisites: the **Connect IQ SDK** and a JDK. Paths live in `build_config.json` (auto-created on first run) — edit them to match your machine:

```json
{
  "JavaHome": "C:\\Program Files\\Android\\openjdk\\jdk-21.0.8",
  "SdkDir":   "C:\\Users\\<you>\\AppData\\Roaming\\Garmin\\ConnectIQ\\Sdks\\<sdk-version>"
}
```

### Build (default device = `fenix847mm`, 454×454)

```powershell
./build.ps1                     # build .prg
./build.ps1 -Device fenix843mm  # build the 416×416 variant
./build.ps1 -Export             # package a store-ready .iq
```

### Build + launch in the simulator

```powershell
./build.ps1 -Run                # or double-click run_simulator.bat
```

In the simulator you can exercise the design via the menus:
- **Settings → Battery** to move the device-battery complication.
- **Simulation → Body Battery** for the Body Battery percentage.
- **Simulation → Time / Sleep** (Always On) to preview the low-power render path.
- **Simulation → Set Time** to test different hour transitions (morning, noon, sunset, and night).

### Sideload to the watch

1. Build the `.prg` (or `.iq`).
2. Connect the watch by USB; it mounts as a drive.
3. Copy `bin/Summertime.prg` to `GARMIN/APPS/` on the device.
4. Eject and select **Summertime** from the watch face list.

For store distribution, upload the `.iq` from `./build.ps1 -Export`.

## Fonts & Typography

The face renders using custom rasterized bitmap fonts:

- **Time font**: *Arial Rounded MT Bold* (`exocet_time.fnt`/`.png`).
- **Date / Metrics font**: *Segoe UI Light* (`exocet_label.fnt`/`.png`).

The bitmap font pipeline is:

```
fonts-src/RoundedTime.ttf  ──┐
fonts-src/SegoeUILight.ttf ──┤  python tools/gen_fonts.py
                             └─▶  resources/fonts/exocet_*.fnt + .png
```

- `tools/gen_fonts.py` rasterizes the glyphs we use (digits, symbols like `:` and `%`, and standard letters) into alpha atlases so `dc.setColor()` tints them. Re-run it if you need to modify font sizes or support new characters.
- `resources/fonts/fonts.xml` declares `ExocetTime` / `ExocetValue` / `ExocetLabel`.
- `initFonts()` loads them, falling back to vector fonts then built-ins if missing.

## Customizing

- **Colors / palettes**: wave, tree, cloud, and sky gradient palettes are constants and function calculations inside `SummertimeView.mc`.
- **Layout anchors**: all coordinate scales are relative percentage values in `onUpdate()`.
