# Summertime Watch Face
 
A premium, golden-hour beach themed **digital watch face** for the **Garmin Fenix 8 and tactix 8**, written in Monkey C for Connect IQ.

Summertime brings a warm, relaxing, and beautiful tropical beach aesthetic to your watch:
 
- **Living Sky Procedural Backdrop**: A smooth color gradient shifting through sunrise pastels, midday azure, sunset marigold, and a starry deep night backdrop based on the current hour.
- **Arcing Celestial Objects**: A glowing sun (with rotating rays and procedural bloom) and a crescent silver moon rise and set along a circular path according to the clock.
- **Drifting Clouds & Rolling Waves**: Fluffy clouds drift across the sky, and overlapping wave layers roll gently at the bottom with real-time wave physics in active mode.
- **Swaying Palm Silhouette**: A segmented palm trunk and wind-swept fronds sway in the breeze at the shoreline.
- **Citrus Slice Seconds**: A floating orange slice second indicator orbits the outer perimeter.
- **Centered Digital Time**: Large, clean, rounded clock numerals (Arial Rounded MT Bold) centered with high-contrast black outlining.
- **Centered Date & Weather**: An elegant date line (Segoe UI Light) showing the calendar date and dynamic weather temperature (with automatic Celsius/Fahrenheit unit conversion).
- **Symmetrical Complications Layout**:
  - **Left complication**: A coral-colored heart icon + numeric Body Battery percentage.
  - **Right complication**: A turquoise-colored water droplet icon + numeric Device Battery percentage.
  - **Bottom complication**: A steps progress bar (XP style, sand/gold themed) + steps numeric count.
- **High-Contrast Text Outlines**: All text elements (clock, date, and metrics) are drawn with a custom black outline to ensure legibility against any dynamic gradient or wave background.

## Hardware / scaling

The project targets the Fenix 8 and tactix 8 platforms. Connect IQ has no dedicated `tactix8` product id, so the project targets the Fenix 8 AMOLED and Solar products:

| Product id      | Resolution | Case            | Panel Type |
|-----------------|------------|-----------------|------------|
| `fenix847mm`    | 454×454    | tactix 8 51mm   | AMOLED     |
| `fenix843mm`    | 416×416    | tactix 8 47mm   | AMOLED     |
| `fenix8pro47mm` | 454×454    | Fenix 8 Pro     | AMOLED     |
| `fenix8solar51mm` / `fenix8solar47mm` | 280/260 | Fenix 8 Solar | MIP (Solar) |

Everything is laid out in percentages of `dc.getWidth()/getHeight()` and the screen center, so it scales cleanly across all of these resolutions.

## Always-on display

The face has two render paths sharing one `onUpdate()`:

- **Active mode** — full brightness, animations (waves, swaying palm, sun rotation, drifting clouds), sky gradients, and text outlines.
- **Always-on / low-power** (`mIsSleep`) — burn-in-safe: dim grey time/date, thin outline representations of the battery metrics, steps progress outline, and **no visual fills or background animations**. All lit pixels are shifted a few pixels each minute (`requiresBurnInProtection`). `onPartialUpdate()` only repaints when the minute changes, staying well inside the always-on power budget.

## Data sources

- **Steps + goal:** `ActivityMonitor.getInfo()` (`steps`, `stepGoal`).
- **Device battery:** `System.getSystemStats().battery`.
- **Body Battery:** `SensorHistory.getBodyBatteryHistory()`. Fails gracefully if the value is unavailable.
- **Weather:** `Weather.getCurrentConditions()` (uses Connect IQ weather APIs to display current temperature in Celsius or Fahrenheit depending on device settings).

## Settings

Editable in Garmin Connect / the simulator's App Settings:

- **Show Date** — toggle the date and weather line.
- **Step Goal Override** — steps for a full shoreline bar; `0` uses the watch's own step goal.

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
