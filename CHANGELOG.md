# Changelog

All notable changes to Summertime are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-06-15

### Added
- **Broad device support**: Summertime now targets every Connect IQ 4.0+ round watch that supports watch faces — Forerunner (incl. **965 / 970**), fenix 7/8, epix 2 / Pro, enduro 3, Venu 2/3, Vivoactive 5/6, Instinct 3 / E / Crossover, and the Approach (golf), Descent (dive), D2 (aviation), and MARQ specialty watches. Edge bike computers, handheld GPS units, and square/rectangular panels (Venu Sq 2, Venu X1) are excluded.
- **Per-resolution bitmap fonts for all panel sizes**: `tools/gen_fonts.py` now bakes a correctly-sized Exocet font set for each distinct round resolution (454, 416, 390, 360, 280, 260, 240, 218, 176, 166), and `monkey.jungle` maps every product to its set.

## [1.1.0] - 2026-06-15

### Added
- **Configurable Complications**: The bottom-left and bottom-right complications are each chosen in the app settings — Heart Rate, Body Battery, Device Battery, Steps, Calories, or Off — and the watch draws a matching icon (heart, bolt, battery, shoe, flame). Each option shows an emoji in the Garmin Connect picker.
- **Heart Rate complication**: Live BPM from the optical HR sensor, cached and sampled at most once every ~10 seconds to stay within the watch-face power budget.
- **Real Sunrise/Sunset**: The sun, day/night swap, stars, and sky gradient now track the actual sunrise/sunset computed from the watch's last-known location and today's date (NOAA almanac formula, cached per day), with a fixed summer-schedule fallback when no location fix is available.

### Changed
- **Device Battery complication** now uses a battery icon with a live fill bar (previously a water droplet).
- **Default complications**: bottom-left = Heart Rate, bottom-right = Device Battery.
- **Citrus-slice seconds indicator** now has a dark rind border so it stays legible against the bright sky and sand.

## [1.0.0]

### Added
- **Initial release of Summertime watch face** for Garmin tactix 8 and Fenix 8 devices (AMOLED + Solar variants).
- **Living Sky Procedural Backdrop**: Smooth color gradient shifting through sunrise pastels, midday azure, sunset marigold, and a starry night backdrop based on the current hour.
- **Arcing Sun & Moon**: Day/night orbital progression of a glowing sun (with rotating rays and bloom) and crescent moon.
- **Drifting Clouds & Rolling Waves**: Fluid wave-motion simulation and wind-drifting clouds.
- **Segmented Palm Silhouette**: Swaying palm tree trunk and fronds responsive to dynamic wind.
- **Citrus Slice Seconds**: Floating orange slice second indicator orbiting the outer perimeter.
- **Symmetrical Complications Layout**:
  - Heart icon (larger scale, 16px with black outline) + numeric Body Battery percentage.
  - Droplet icon (larger scale, 12px with black outline) + numeric Device Battery percentage.
  - Steps progress bar (sand/gold themed) + steps numeric display.
- **High-Contrast Text Outlines**: Dynamic black text outlining on all elements (clock, date, steps, battery, and body battery values) for supreme legibility against moving backdrops.
- **Dimmed Low-Power Render Path**: Burn-in safe ambient mode for AMOLED screens with coordinate shifting.
- **Custom Fonts**: *Arial Rounded MT Bold* clock font and *Segoe UI Light* labeling/date fonts.
