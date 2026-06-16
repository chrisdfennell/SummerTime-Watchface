import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.SensorHistory;
import Toybox.Position;
import Toybox.Math;
import Toybox.Weather;

//
// Summertime - a golden-hour beach watch face.
//
//   - Center:  large digital time (Rounded) + elegant date line (Segoe UI)
//   - Left:    configurable complication (default heart rate)
//   - Right:   configurable complication (default device battery)
//   - Bottom:  steps progress bar, styled as a shoreline sand/gold bar
//   - Background: living sky gradient, arcing sun/moon, drifting clouds, rolling
//                 waves, and a swaying palm tree
//
// The two bottom complications are chosen in the app settings (heart rate, Body
// Battery, device battery, steps, or calories) and each draws a matching icon.
// The sun, day/night, stars, and sky track the REAL sunrise/sunset computed from
// the watch's location and today's date, falling back to a fixed summer schedule
// when no location fix is available.
//
// Everything scales cleanly relative to the screen dimensions (dc.getWidth()/getHeight()).
//
class SummertimeView extends WatchUi.WatchFace {

    // --- Screen geometry (resolved in onLayout) ---
    private var mWidth as Number = 0;
    private var mHeight as Number = 0;
    private var mCenterX as Number = 0;
    private var mCenterY as Number = 0;

    // --- State ---
    private var mIsSleep as Boolean = false;
    private var mLowPower as Boolean = false;  // true only on AMOLED in Always-On (burn-in) mode
    private var mFlatGlobes as Boolean = false; // true on MIP: flat 2-tone fills (no banded gradient)
    private var mLastMin as Number = -1;       // throttles low-power partial updates

    // --- Complication option ids (must match resources/settings list values) ---
    private const COMP_OFF      = 0;
    private const COMP_HR       = 1;  // heart rate (BPM)
    private const COMP_BODY     = 2;  // Body Battery (%)
    private const COMP_BATTERY  = 3;  // device battery (%)
    private const COMP_STEPS    = 4;  // step count
    private const COMP_CALORIES = 5;  // calories (kcal)

    // --- Critter ids (the little beach visitors that cross the screen) ---
    private const CR_CRAB    = 0;  // beach (ground), day or night - scuttles sideways
    private const CR_SEAGULL = 1;  // flies in, lands on the sand, walks, takes off (day)
    private const CR_DOLPHIN = 2;  // leaps from the sea in an arc, day or night
    private const CR_WHALE   = 3;  // breaches from the sea, day or night

    // --- Settings (see resources/settings) ---
    private var mShowDate as Boolean = true;
    private var mStepGoalOverride as Number = 0;  // 0 => use device step goal
    private var mLeftComp as Number = COMP_HR;       // bottom-left complication
    private var mRightComp as Number = COMP_BATTERY; // bottom-right complication
    private var mShowCritters as Boolean = true;     // the crossing beach visitors

    // --- Heart-rate cache (sensor read throttled to once every ~10s) ---
    private var mCachedHr as Number or Null = null;
    private var mHrLastSec as Number = -100;

    // --- Sunrise/sunset cache (recomputed when the day or first fix changes) ---
    private var mSunDay as Number = -1;        // day-of-year the times were computed for
    private var mSunValid as Boolean = false;  // true once a real location fix was used
    private var mSunrise as Float = 6.0;       // local hours; defaults = fixed summer schedule
    private var mSunset as Float = 18.0;
    private var mSunLastTry as Number = -10000; // epoch sec of last (not-yet-valid) sun retry

    // --- Per-frame cache of device settings (read once per redraw) ---
    private var mSettings as System.DeviceSettings or Null = null;

    // --- Fonts (vector fonts with safe fallbacks) ---
    private var mFontTime as Graphics.FontType or Null = null;
    private var mFontDate as Graphics.FontType or Null = null;
    private var mFontValue as Graphics.FontType or Null = null;
    private var mFontLabel as Graphics.FontType or Null = null;

    // --- Color Palettes ----------------------------------------------------
    // Body Battery globe = coral/peach
    private const C_BODY_BRIGHT = 0xFF7B60;
    private const C_BODY_DARK   = 0x4A1E1E;
    private const C_BODY_RIM    = 0xFFAD87;
    private const C_BODY_GLOW   = 0x6A2820;

    // Device battery globe = soft turquoise
    private const C_BATT_BRIGHT = 0x8FE5D9;
    private const C_BATT_DARK   = 0x153A3A;
    private const C_BATT_RIM    = 0x40C0B0;
    private const C_BATT_GLOW   = 0x155A50;

    // Steps bar = warm gold / sand
    private const C_XP_TRACK    = 0x2A2015;
    private const C_XP_FILL     = 0xFF7B60;
    private const C_XP_BRIGHT   = 0xFFC043;
    private const C_XP_GLOW     = 0x6A4810;
    private const C_XP_BORDER   = 0xFFF4E0;

    private const BG_COLOR = 0x000000;        // pitch black for AMOLED contrast/battery

    // --- Hoisted constants (avoid re-allocating these arrays every frame) ---
    // Star field positions, expressed against a 454x454 reference and scaled.
    private const STAR_X = [70, 120, 180, 240, 310, 380, 90, 150, 220, 290, 360, 130, 200, 270, 340, 110, 250, 330] as Array<Number>;
    private const STAR_Y = [50, 70, 45, 60, 55, 75, 110, 95, 120, 105, 115, 160, 150, 175, 155, 200, 210, 195] as Array<Number>;
    // Sky gradient keyframe colors (identical for the real-sun and fallback schedules).
    private const SKY_TOP    = [0x050515, 0x0A0E29, 0x4A7A96, 0x1D8CF8, 0x1DA1F2, 0x3A86C8, 0xFF6F7D, 0x0F1123, 0x050515] as Array<Number>;
    private const SKY_BOTTOM = [0x0A0A25, 0x2C1B4D, 0xFF7B60, 0x8FE5D9, 0xFFF4E0, 0xFFAD87, 0xFFC043, 0x5C2E58, 0x0A0A25] as Array<Number>;
    // Fixed-summer fallback keyframe hours, used when no real sun fix is available.
    private const SKY_HOURS_FALLBACK = [0.0, 5.0, 7.0, 10.0, 14.0, 17.0, 19.5, 21.0, 24.0] as Array<Float>;

    // Reusable polygon buffer for the rolling waves (filled in place each frame
    // instead of allocating a new array + point pairs on every redraw).
    private var mWavePts as Array or Null = null;

    // --- Per-frame caches (read once per redraw to avoid duplicate syscalls) ---
    private var mClock as System.ClockTime or Null = null;
    private var mActInfo as ActivityMonitor.Info or Null = null;

    // --- Cached AMOLED sky-gradient buffer ---------------------------------
    // The gradient colors depend only on hour+minute, so they change at most
    // once a minute. We render the ~86-row fill into a buffered bitmap once and
    // just blit it on subsequent (per-second) frames, re-rendering only when the
    // colors or dimensions change. Only used on AMOLED (MIP uses a flat fill).
    private var mSkyBufRef as Graphics.BufferedBitmapReference or Null = null;
    private var mSkyKeyTop as Number = -1;
    private var mSkyKeyBottom as Number = -1;
    private var mSkyKeyW as Number = -1;
    private var mSkyKeyH as Number = -1;

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    // Read user settings; safe to call any time.
    function loadSettings() as Void {
        try {
            if (Application has :Properties) {
                var showDate = Application.Properties.getValue("ShowDate");
                var stepGoal = Application.Properties.getValue("StepGoalOverride");
                var leftComp = Application.Properties.getValue("LeftComplication");
                var rightComp = Application.Properties.getValue("RightComplication");
                var critters = Application.Properties.getValue("ShowCritters");
                if (showDate != null) { mShowDate = showDate; }
                if (stepGoal != null) { mStepGoalOverride = stepGoal; }
                if (leftComp != null) { mLeftComp = leftComp; }
                if (rightComp != null) { mRightComp = rightComp; }
                if (critters != null) { mShowCritters = critters; }
            }
        } catch (e) {
            // keep defaults
        }
        if (mStepGoalOverride < 0) { mStepGoalOverride = 0; }
    }

    function onLayout(dc as Dc) as Void {
        mWidth = dc.getWidth();
        mHeight = dc.getHeight();
        mCenterX = mWidth / 2;
        mCenterY = mHeight / 2;
        initFonts();
    }

    // Custom fonts generated by gen_fonts.py are loaded here.
    function initFonts() as Void {
        try {
            mFontTime  = WatchUi.loadResource(Rez.Fonts.ExocetTime) as Graphics.FontType;
            mFontValue = WatchUi.loadResource(Rez.Fonts.ExocetValue) as Graphics.FontType;
            mFontLabel = WatchUi.loadResource(Rez.Fonts.ExocetLabel) as Graphics.FontType;
            mFontDate  = mFontLabel;
        } catch (e) {
            mFontTime = null;
            mFontValue = null;
            mFontLabel = null;
            mFontDate = null;
        }

        // Vector-font fallback for anything that didn't load.
        if (Graphics has :getVectorFont) {
            var bold = ["RobotoCondensedBold", "RobotoRegular", "sans-serif"] as Array<String>;
            if (mFontTime == null)  { mFontTime  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.21).toNumber() }); }
            if (mFontDate == null)  { mFontDate  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.058).toNumber() }); }
            if (mFontValue == null) { mFontValue = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.085).toNumber() }); }
            if (mFontLabel == null) { mFontLabel = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.044).toNumber() }); }
        }

        // Built-in last resort.
        if (mFontTime == null)  { mFontTime  = Graphics.FONT_NUMBER_THAI_HOT; }
        if (mFontDate == null)  { mFontDate  = Graphics.FONT_TINY; }
        if (mFontValue == null) { mFontValue = Graphics.FONT_MEDIUM; }
        if (mFontLabel == null) { mFontLabel = Graphics.FONT_XTINY; }
    }

    function onShow() as Void {
        loadSettings();
    }

    // Single render entry point for both active and low-power frames.
    function onUpdate(dc as Dc) as Void {
        var w = mWidth;
        var h = mHeight;

        var settings = System.getDeviceSettings();
        mSettings = settings;  // cache for drawTime / getWeatherString this frame
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        var burnIn = hasBurnIn && mIsSleep;
        var dx = 0;
        var dy = 0;
        if (burnIn) {
            var shift = computeBurnInShift();
            dx = shift[0];
            dy = shift[1];
        }
        mLowPower = burnIn;
        mFlatGlobes = !hasBurnIn;

        var cx = mCenterX + dx;
        var cy = mCenterY + dy;

        // 1. Clear to pitch black
        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        // Time values (cache the clock + activity info once for this redraw)
        var clockTime = System.getClockTime();
        mClock = clockTime;
        mActInfo = ActivityMonitor.getInfo();
        var hour = clockTime.hour;
        var min = clockTime.min;
        var secVal = clockTime.sec;

        if (!mLowPower) {
            // --- ACTIVE VISUAL LAYER ---

            // A. Resolve today's sunrise/sunset (cached), then get the living
            //    sky gradient colors for the current time.
            updateSunTimes();
            var skyColors = getSkyColors(hour, min);
            var cTop = skyColors[0];
            var cBottom = skyColors[1];

            // B. Draw Sky
            var skyH = (h * 0.76).toNumber();
            if (mFlatGlobes) {
                // MIP: Solid fill to prevent ugly banding
                dc.setColor(cTop, cTop);
                dc.fillRectangle(0, 0, w, skyH);
            } else {
                // AMOLED: smooth gradient, cached in a buffer so the per-row fill
                // loop runs at most once a minute (when the colors change) rather
                // than on every per-second redraw.
                var skyBmp = getSkyBitmap(w, skyH, cTop, cBottom);
                if (skyBmp != null) {
                    dc.drawBitmap(0, 0, skyBmp);
                } else {
                    // Fallback: render the gradient directly (no buffered bitmap).
                    var step = 4;
                    for (var y = 0; y < skyH; y += step) {
                        var frac = y.toFloat() / skyH.toFloat();
                        var c = lerpColor(cTop, cBottom, frac);
                        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                        dc.fillRectangle(0, y, w, step);
                    }
                }
            }

            // C. Draw Stars at night (real sunset -> sunrise window)
            var tNow = hour.toFloat() + min.toFloat() / 60.0;
            var isNight = !(tNow >= mSunrise && tNow < mSunset);
            if (isNight) {
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                for (var i = 0; i < STAR_X.size(); i++) {
                    var sx = (STAR_X[i] * w / 454).toNumber();
                    var sy = (STAR_Y[i] * h / 454).toNumber();
                    dc.drawPoint(sx, sy);
                }
            }

            // D. Draw Arcing Sun / Moon along the real day arc
            var dayStart = mSunrise;
            var dayEnd = mSunset;
            var t = tNow;
            var isDay = !isNight;
            var arcR = (w * 0.38).toNumber();
            var arcCenterY = (h * 0.68).toNumber();

            var angle = 0.0;
            if (isDay) {
                angle = Math.PI - (Math.PI * (t - dayStart) / (dayEnd - dayStart));
            } else {
                var tNight = (t < dayStart) ? (t + (24.0 - dayEnd)) : (t - dayEnd);
                angle = Math.PI - (Math.PI * tNight / (24.0 - (dayEnd - dayStart)));
            }
            var sx = cx + (arcR * Math.cos(angle)).toNumber();
            var sy = arcCenterY - (arcR * Math.sin(angle)).toNumber();

            if (isDay) {
                var sunR = (w * 0.065).toNumber();
                var sunSkyFrac = sy.toFloat() / skyH.toFloat();
                if (sunSkyFrac < 0.0) { sunSkyFrac = 0.0; }
                if (sunSkyFrac > 1.0) { sunSkyFrac = 1.0; }
                var sunSkyColor = lerpColor(cTop, cBottom, sunSkyFrac);

                // Rays rotation based on seconds
                dc.setColor(0xFFC043, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                var numRays = 8;
                var secOffset = secVal.toFloat() * 0.02;
                for (var i = 0; i < numRays; i++) {
                    var rayAngle = (i * (2.0 * Math.PI / numRays)) + secOffset;
                    var rx1 = (sx + (sunR + 2) * Math.cos(rayAngle)).toNumber();
                    var ry1 = (sy + (sunR + 2) * Math.sin(rayAngle)).toNumber();
                    var rx2 = (sx + (sunR + 8) * Math.cos(rayAngle)).toNumber();
                    var ry2 = (sy + (sunR + 8) * Math.sin(rayAngle)).toNumber();
                    dc.drawLine(rx1, ry1, rx2, ry2);
                }

                // Procedural bloom
                dc.setColor(lerpColor(sunSkyColor, 0xFFD060, 0.25), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR + 6);
                dc.setColor(lerpColor(sunSkyColor, 0xFFD060, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR + 3);

                // Core
                dc.setColor(0xFFD060, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR);
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR - 4);
            } else {
                var moonR = (w * 0.055).toNumber();
                var moonSkyFrac = sy.toFloat() / skyH.toFloat();
                if (moonSkyFrac < 0.0) { moonSkyFrac = 0.0; }
                if (moonSkyFrac > 1.0) { moonSkyFrac = 1.0; }
                var moonSkyColor = lerpColor(cTop, cBottom, moonSkyFrac);

                // Silver base circle
                dc.setColor(0xE2E2E2, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, moonR);
                // Offset circle of sky color to mask crescent
                dc.setColor(moonSkyColor, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx + 5, sy - 2, moonR);
            }

            // E. Draw Drifting Clouds
            var cloudOffset = (min * 60 + secVal).toFloat();
            var span = w + 80;
            // Positive modulo: Monkey C's % keeps the sign of the dividend, so a
            // negative drift (cloud 2) would otherwise wrap off-screen.
            var cx1 = (((((w * 0.1 + (cloudOffset * 0.08)).toNumber()) % span) + span) % span) - 40;
            var cx2 = (((((w * 0.7 - (cloudOffset * 0.05)).toNumber()) % span) + span) % span) - 40;
            drawCloud(dc, cx1, (h * 0.20).toNumber());
            drawCloud(dc, cx2, (h * 0.28).toNumber());

            // Resolve which little visitor (if any) is crossing right now, so a
            // breaching sea creature can be drawn between the wave layers and a
            // shore visitor in front of the beach.
            var crit = mShowCritters ? computeCritter(hour, min, secVal, isNight) : null;

            // F. Draw Rolling Waves (sine-wave polygons). A breaching whale or
            //    leaping dolphin is drawn between the back and front wave so the
            //    water hides the base of the splash.
            var wavePhase1 = secVal.toFloat() * 0.07;
            var wavePhase2 = -secVal.toFloat() * 0.10;
            // Back wave
            drawWave(dc, (h * 0.76).toNumber(), 5, 45.0, wavePhase1, 0x1A6B9C);
            if (crit != null && isWaterCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }
            // Front wave
            drawWave(dc, (h * 0.80).toNumber(), 6, 35.0, wavePhase2, 0x40C0B0);

            // G. Draw Beach Shoreline
            var beachY = (h * 0.88).toNumber();
            dc.setColor(0xFFF4E0, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, beachY, w, h - beachY);

            // H. Draw Swaying Palm Tree
            var palmSway = 0.08 * Math.sin(secVal.toFloat() * 0.15);
            drawPalmTree(dc, (w * 0.86).toNumber(), beachY, (w * 0.80).toNumber(), (h * 0.54).toNumber(), palmSway);

            // I. Shore visitors (crab scuttling, seagull flying / walking) are
            //    drawn in front of the beach and palm.
            if (crit != null && !isWaterCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }
        }

        // --- Center Clock & Date ---
        drawTime(dc, cx, cy - (h * 0.05).toNumber());
        if (mShowDate) {
            drawDate(dc, cx, cy + (h * 0.06).toNumber());
        }

        // --- Bottom Beach Complications (Symmetrical Layout) ---
        var metricsY = (h * 0.815).toNumber() + dy;
        var leftX    = (w * 0.22).toNumber() + dx;
        var rightX   = (w * 0.78).toNumber() + dx;

        // Bottom complications are user-configurable (see resources/settings).
        drawComplication(dc, leftX, metricsY, mLeftComp);
        drawComplication(dc, rightX, metricsY, mRightComp);

        // Steps Progress Bar & Numeric Text (Centered)
        var barW = (w * 0.38).toNumber();
        var barH = 8;
        var barY = (h * 0.91).toNumber() + dy;
        var stepsFraction = getStepFraction();
        drawXpBar(dc, cx, barY, barW, barH, stepsFraction);
        
        if (!burnIn) {
            var actInfo = mActInfo;
            var steps = (actInfo != null && actInfo.steps != null) ? actInfo.steps : 0;
            var stepsStr = steps.format("%d") + " STEPS";
            drawTextWithOutline(dc, cx, barY - 14, mFontLabel, stepsStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, 0xFFFFFF);
        }

        // --- Orbiting "tiny sun" seconds marker (citrus slice) -------------
        // Drawn LAST so it always sits ABOVE the time, date, complications and
        // steps bar, instead of being hidden behind the bottom text.
        if (!mLowPower) {
            var secAngle = (secVal * 6.0) * Math.PI / 180.0;
            var secRadius = (w * 0.44).toNumber() - 10;
            var csx = cx + (secRadius * Math.sin(secAngle)).toNumber();
            var csy = cy - (secRadius * Math.cos(secAngle)).toNumber();
            drawCitrusSlice(dc, csx, csy);
        }
    }

    // Anti-burn-in pixel shift for AMOLED always-on mode. Cycles through a few
    // small offsets so static pixels are not lit identically minute after minute.
    private function computeBurnInShift() as Array<Number> {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var phase = clock.min % 4;
        if (phase == 1)      { return [4, 2] as Array<Number>; }
        else if (phase == 2) { return [-3, 4] as Array<Number>; }
        else if (phase == 3) { return [3, -4] as Array<Number>; }
        return [0, 0] as Array<Number>;
    }

    // ------------------------------------------------------------------ Elements

    function drawTime(dc as Dc, cx as Number, cy as Number) as Void {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var hour = clock.hour;
        var min = clock.min;
        var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
        var is24 = settings.is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hourStr = is24 ? hour.format("%02d") : hour.format("%d");
        var timeStr = hourStr + ":" + min.format("%02d");

        // Dim in AOD, bright cream-white otherwise
        var color = mLowPower ? 0x6E6E6E : 0xFFF4E0;
        drawTextWithOutline(dc, cx, cy, mFontTime, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    function drawDate(dc as Dc, cx as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week.toUpper() + "   " + info.month.toUpper() + " " + info.day;
        
        // Append weather if available. Skipped in always-on/low-power so the
        // weather lookup never runs inside the partial-update budget (and so the
        // dim AOD date stays consistent between full and partial redraws).
        var weatherStr = mLowPower ? null : getWeatherString();
        if (weatherStr != null) {
            dateStr = dateStr + "   •   " + weatherStr;
        }

        // Dim in AOD, light elegant peach otherwise
        var color = mLowPower ? 0x555555 : 0xFF7B60;
        drawTextWithOutline(dc, cx, y, mFontDate, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    private function drawCloud(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(0xFFF4E0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 12, y, 10);
        dc.fillCircle(x + 12, y, 10);
        dc.fillCircle(x, y - 5, 14);
        dc.fillRectangle(x - 12, y - 2, 24, 12);
    }

    private function drawWave(dc as Dc, yBase as Number, amp as Number, waveLen as Float, phase as Float, color as Number) as Void {
        var w = mWidth;
        var h = mHeight;
        
        var steps = 12;
        var stepW = w / steps;
        // Reuse a persistent buffer (and its point pairs) instead of allocating
        // a fresh array + 15 sub-arrays on every frame.
        if (mWavePts == null) {
            var buf = new [steps + 3] as Array<Array>;
            for (var k = 0; k < steps + 3; k++) { buf[k] = [0, 0]; }
            mWavePts = buf;
        }
        var points = mWavePts;
        points[0][0] = w; points[0][1] = h;
        points[1][0] = 0; points[1][1] = h;

        for (var i = 0; i <= steps; i++) {
            var x = i * stepW;
            var angle = (x.toFloat() / waveLen) + phase;
            var y = yBase + (amp * Math.sin(angle)).toNumber();
            points[i + 2][0] = x;
            points[i + 2][1] = y;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }

    private function drawPalmTree(dc as Dc, tx as Number, ty as Number, cx as Number, cy as Number, sway as Float) as Void {
        // Draw trunk
        var trunkSteps = 12;
        var trunkColor = 0x241C10; // Dark brown
        dc.setColor(trunkColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i <= trunkSteps; i++) {
            var t = i.toFloat() / trunkSteps.toFloat();
            var x = (tx + (cx - tx) * t - 8.0 * Math.sin(t * Math.PI)).toNumber();
            var y = (ty + (cy - ty) * t).toNumber();
            var r = (7.0 - 3.5 * t).toNumber();
            if (r < 2) { r = 2; }
            dc.fillCircle(x, y, r);
        }

        // Draw 5 leaves with wind sway
        var leafLen = (mWidth * 0.08).toNumber();
        var leafColor = 0x1A2812; // Silhouette green
        drawPalmLeaf(dc, cx, cy, -2.6 + sway, leafLen, leafColor);
        drawPalmLeaf(dc, cx, cy, -1.9 + sway, leafLen, leafColor);
        drawPalmLeaf(dc, cx, cy, -1.2 + sway, leafLen, leafColor);
        drawPalmLeaf(dc, cx, cy, -0.5 + sway, leafLen, leafColor);
        drawPalmLeaf(dc, cx, cy, 0.2 + sway, leafLen, leafColor);
    }

    private function drawPalmLeaf(dc as Dc, lx as Number, ly as Number, angle as Float, length as Number, leafColor as Number) as Void {
        var steps = 7;
        var stepLen = length / steps;
        var prevX = lx;
        var prevY = ly;
        
        for (var i = 1; i <= steps; i++) {
            var t = i.toFloat() / steps.toFloat();
            var curAngle = angle + 0.25 * t * t; 
            var curX = (lx + i * stepLen * Math.cos(curAngle)).toNumber();
            var curY = (ly + i * stepLen * Math.sin(curAngle)).toNumber();
            
            dc.setColor(leafColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(prevX, prevY, curX, curY);
            
            dc.setPenWidth(1);
            var frondLen = (11.0 * Math.sin(t * Math.PI)).toNumber();
            if (frondLen < 3) { frondLen = 3; }
            
            var perpAngle = curAngle + Math.PI / 2.0;
            var fx1 = (curX + frondLen * Math.cos(perpAngle)).toNumber();
            var fy1 = (curY + frondLen * Math.sin(perpAngle)).toNumber();
            var fx2 = (curX - frondLen * Math.cos(perpAngle)).toNumber();
            var fy2 = (curY - frondLen * Math.sin(perpAngle)).toNumber();
            
            dc.drawLine(curX, curY, fx1, fy1);
            dc.drawLine(curX, curY, fx2, fy2);
            
            prevX = curX;
            prevY = curY;
        }
    }

    private function drawCitrusSlice(dc as Dc, sx as Number, sy as Number) as Void {
        var orange = 0xFF9E79;
        var white = 0xFFFFFF;

        // Dark rind border so the slice stays legible against the bright sky/sand.
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 10);

        dc.setColor(orange, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 8);
        
        dc.setColor(white, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(sx, sy, 6);
        dc.fillCircle(sx, sy, 5);
        
        dc.setColor(orange, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 4);
        
        dc.setColor(white, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var a = 0; a < 360; a += 60) {
            var rad = a * Math.PI / 180.0;
            var dx = (5 * Math.cos(rad)).toNumber();
            var dy = (5 * Math.sin(rad)).toNumber();
            dc.drawLine(sx, sy, sx + dx, sy + dy);
        }
    }

    private function drawSummerBezel(dc as Dc, gx as Number, gy as Number, r as Number, lit as Boolean) as Void {
        var gold      = lit ? 0xFFC043 : 0x8A6A3A;
        var sand      = lit ? 0xFFF4E0 : 0xEDE0C0;
        var glowColor = lit ? 0xFFD060 : 0x6A4810;
        
        if (lit) {
            dc.setPenWidth(4);
            dc.setColor(scaleColor(glowColor, 0.4), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
        }
        
        dc.setPenWidth(3);
        dc.setColor(sand, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 1);
        
        dc.setPenWidth(1);
        dc.setColor(gold, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r - 1);
    }

    // Liquid-fill globe.
    function drawGlobe(dc as Dc, gx as Number, gy as Number, r as Number,
                       value as Number, available as Boolean,
                       bright as Number, dark as Number, rim as Number, glow as Number) as Void {
        if (mLowPower) {
            drawGlobeLowPower(dc, gx, gy, r, value, available, rim);
            return;
        }

        // 1. Soft outer glow
        if (available && value > 0 && !mFlatGlobes) {
            dc.setPenWidth(3);
            dc.setColor(scaleColor(glow, 0.60), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
            dc.setPenWidth(2);
            dc.setColor(scaleColor(glow, 0.30), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 5);
        }

        // 2. Dark glass sphere base.
        dc.setColor(scaleColor(dark, 0.55), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, r);

        // 3. Liquid fill
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var fillH = (2.0 * r) * v / 100.0;
            var surfaceY = ((gy + r) - fillH).toNumber();
            var bottomY = gy + r - 1;
            var flatTop = bright;
            var flatBottom = lerpColor(bright, dark, 0.5);
            var step = 2;
            for (var y = surfaceY; y <= bottomY; y += step) {
                var half = chordHalf(r - 1, y - gy);
                if (half < 1) { continue; }
                var depth = (y - surfaceY).toFloat() / fillH;
                var c;
                if (mFlatGlobes) {
                    c = (depth < 0.55) ? flatTop : flatBottom;
                } else {
                    var t = 1.0 - depth;
                    if (t < 0.0) { t = 0.0; }
                    if (t > 1.0) { t = 1.0; }
                    c = lerpColor(dark, bright, t);
                }
                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(gx - half, y, 2 * half, step);
            }

            // Molten core
            if (fillH > r * 0.5 && !mFlatGlobes) {
                var coreY = (gy + r - fillH * 0.45).toNumber();
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.10), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.22).toNumber());
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.22), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.10).toNumber());
            }

            // Bright meniscus line
            var mHalf = chordHalf(r, surfaceY - gy);
            if (mHalf > 1) {
                dc.setPenWidth(2);
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - mHalf, surfaceY, gx + mHalf, surfaceY);
            }
        }

        // 4. Specular glass highlight
        if (available) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(gx - (r * 0.34).toNumber(), gy - (r * 0.42).toNumber(), (r * 0.12).toNumber());
        }

        // 5. Bezel
        drawSummerBezel(dc, gx, gy, r, (available && value > 0));
    }

    // Burn-in-safe globe: just a thin dim ring + a thin fluid-level line.
    function drawGlobeLowPower(dc as Dc, gx as Number, gy as Number, r as Number,
                               value as Number, available as Boolean, rim as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(scaleColor(rim, 0.45), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r);
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var surfaceY = ((gy + r) - (2.0 * r) * v / 100.0).toNumber();
            var half = chordHalf(r, surfaceY - gy);
            if (half > 1) {
                dc.setColor(scaleColor(rim, 0.65), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - half, surfaceY, gx + half, surfaceY);
            }
        }
    }

    // Steps progress bar
    function drawXpBar(dc as Dc, cx as Number, y as Number, barW as Number, barH as Number, frac as Float) as Void {
        var x = cx - barW / 2;
        var top = y - barH / 2;
        var rad = barH / 2;

        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fw = (barW * frac).toNumber();

        if (mLowPower) {
            dc.setPenWidth(1);
            dc.setColor(scaleColor(C_XP_FILL, 0.40), Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, top, barW, barH, rad);
            if (fw > 2) {
                dc.setColor(scaleColor(C_XP_FILL, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + 2, y, x + fw - 2, y);
            }
            return;
        }

        // Track (dark gold/sand)
        dc.setColor(C_XP_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, barW, barH, rad);

        // Fill (coral progress)
        if (frac > 0.0) {
            if (fw < barH) { fw = barH; }
            if (fw > barW) { fw = barW; }
            dc.setColor(C_XP_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, fw, barH, rad);
        }

        // Summer frame + sun end caps
        dc.setPenWidth(1);
        dc.setColor(C_XP_BORDER, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, top, barW, barH, rad);

        dc.setColor(0xFFC043, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, y, 3);
        dc.fillCircle(x + barW + 2, y, 3);
    }

    // ------------------------------------------------------------------- Data

    function getStepFraction() as Float {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return 0.0; }
        var steps = info.steps;
        var goal = mStepGoalOverride;
        if (goal <= 0) {
            if (info.stepGoal != null && info.stepGoal > 0) {
                goal = info.stepGoal;
            } else {
                goal = 10000;
            }
        }
        if (goal <= 0) { return 0.0; }
        var f = steps.toFloat() / goal.toFloat();
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    function getBodyBattery() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
                var iter = SensorHistory.getBodyBatteryHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        var v = sample.data.toNumber();
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Current heart rate in BPM. The sensor reading is cached and refreshed at
    // most once every ~10 seconds to stay within the watch-face power budget.
    // Returns null when no recent reading is available.
    function getHeartRate() as Number or Null {
        var nowSec = Time.now().value();
        if (mCachedHr != null && (nowSec - mHrLastSec) < 10) {
            return mCachedHr;
        }
        mHrLastSec = nowSec;
        try {
            if (Toybox has :Activity) {
                var info = Activity.getActivityInfo();
                if (info != null && info.currentHeartRate != null) {
                    mCachedHr = info.currentHeartRate;
                    return mCachedHr;
                }
            }
            if ((Toybox has :ActivityMonitor) && (ActivityMonitor has :getHeartRateHistory)) {
                var it = ActivityMonitor.getHeartRateHistory(1, true);
                if (it != null) {
                    var s = it.next();
                    if (s != null && s.heartRate != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                        mCachedHr = s.heartRate;
                        return mCachedHr;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return mCachedHr;
    }

    function getDeviceBattery() as Number {
        var stats = System.getSystemStats();
        return (stats.battery != null) ? stats.battery.toNumber() : 0;
    }

    function getSteps() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.steps != null) ? info.steps : 0;
    }

    function getCalories() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.calories != null) ? info.calories : 0;
    }

    // --------------------------------------------------------- Complications

    // Draw one configurable complication (icon + value) centered on cx.
    private function drawComplication(dc as Dc, cx as Number, y as Number, opt as Number) as Void {
        if (opt == COMP_OFF) { return; }

        var valStr = "--";
        var level = -1;
        var accent = 0xFFFFFF;

        if (opt == COMP_HR) {
            var hr = getHeartRate();
            valStr = (hr != null) ? hr.format("%d") : "--";
            accent = 0xFF7B60;            // coral heart
        } else if (opt == COMP_BODY) {
            var bb = getBodyBattery();
            valStr = (bb != null) ? bb.format("%d") + "%" : "--";
            accent = 0xFFC043;            // warm gold bolt
        } else if (opt == COMP_BATTERY) {
            var b = getDeviceBattery();
            valStr = b.format("%d") + "%";
            level = b;
            accent = 0x40C0B0;            // turquoise battery
        } else if (opt == COMP_STEPS) {
            valStr = getSteps().format("%d");
            accent = 0xFFD8A0;            // sandy boot
        } else if (opt == COMP_CALORIES) {
            valStr = getCalories().format("%d");
            accent = 0xFF6B3D;            // sunset flame
        } else {
            return;
        }

        var textColor = mLowPower ? 0x6E6E6E : 0xFFFFFF;
        var iconColor = mLowPower ? 0x6E6E6E : accent;

        var textWidth = dc.getTextWidthInPixels(valStr, mFontLabel);
        var totalW = 16 + 6 + textWidth;
        var startX = cx - totalW / 2;

        drawComplicationIcon(dc, opt, startX + 8, y, iconColor, level);
        drawTextWithOutline(dc, startX + 22, y, mFontLabel, valStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, textColor);
    }

    private function drawComplicationIcon(dc as Dc, kind as Number, x as Number, y as Number, color as Number, level as Number) as Void {
        if (kind == COMP_HR) {
            drawHeartIcon(dc, x, y, color);
        } else if (kind == COMP_BODY) {
            drawBoltIcon(dc, x, y, color);
        } else if (kind == COMP_BATTERY) {
            drawBatteryIcon(dc, x, y, color, level);
        } else if (kind == COMP_STEPS) {
            drawBootIcon(dc, x, y, color);
        } else if (kind == COMP_CALORIES) {
            drawFlameIcon(dc, x, y, color);
        }
    }

    // Body Battery -> lightning bolt (energy).
    private function drawBoltIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBoltShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x - 1, y - 1);
        drawBoltShape(dc, x + 1, y - 1);
        drawBoltShape(dc, x - 1, y + 1);
        drawBoltShape(dc, x + 1, y + 1);
        drawBoltShape(dc, x - 1, y);
        drawBoltShape(dc, x + 1, y);
        drawBoltShape(dc, x,     y - 1);
        drawBoltShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x, y);
    }

    private function drawBoltShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x + 2, y - 8], [x - 5, y + 1], [x - 1, y + 1],
            [x - 2, y + 8], [x + 5, y - 2], [x + 1, y - 2]
        ] as Array<Array>);
    }

    // Steps -> shoe.
    private function drawBootIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBootShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x - 1, y - 1);
        drawBootShape(dc, x + 1, y - 1);
        drawBootShape(dc, x - 1, y + 1);
        drawBootShape(dc, x + 1, y + 1);
        drawBootShape(dc, x - 1, y);
        drawBootShape(dc, x + 1, y);
        drawBootShape(dc, x,     y - 1);
        drawBootShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x, y);
    }

    private function drawBootShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillRoundedRectangle(x - 4, y - 7, 6, 10, 2);  // leg
        dc.fillRoundedRectangle(x - 4, y + 1, 11, 4, 2);  // foot
    }

    // Calories -> flame.
    private function drawFlameIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawFlameShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x - 1, y - 1);
        drawFlameShape(dc, x + 1, y - 1);
        drawFlameShape(dc, x - 1, y + 1);
        drawFlameShape(dc, x + 1, y + 1);
        drawFlameShape(dc, x - 1, y);
        drawFlameShape(dc, x + 1, y);
        drawFlameShape(dc, x,     y - 1);
        drawFlameShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x, y);
    }

    private function drawFlameShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x, y - 8], [x + 5, y - 1], [x + 4, y + 4], [x - 4, y + 4], [x - 5, y - 1]
        ] as Array<Array>);
        dc.fillCircle(x, y + 2, 4);
    }

    // ------------------------------------------------------------ Critters

    // Decide which little visitor (if any) is crossing the screen right now.
    // Returns [type, dir, frac, seed] or null. At most one critter is ever active,
    // and quiet periods leave the beach empty so it stays calm ("once in a while").
    private function computeCritter(hour as Number, min as Number, sec as Number, isNight as Boolean) as Array or Null {
        var PERIOD = 38.0;  // a visitor may appear once per this many seconds
        var CROSS  = 8.0;   // how long the crossing animation lasts

        var tDay = (hour * 3600 + min * 60 + sec).toFloat();
        var period = (tDay / PERIOD).toNumber();
        var local = tDay - period * PERIOD;

        // ~1 in 5 windows is a quiet stretch with no visitor at all.
        if (period % 5 == 0) { return null; }
        if (local >= CROSS) { return null; }

        var frac = local / CROSS;          // 0..1 progress across the screen
        var dir = ((period * 31 + 7) % 2 == 0) ? 1 : -1;
        var sel = (period * 17 + 5) % 4;

        var type;
        if (isNight) {
            // night pool: crabs are nocturnal; dolphins/whales still surface.
            // No seagulls at night.
            var nightPool = [CR_CRAB, CR_DOLPHIN, CR_CRAB, CR_WHALE] as Array<Number>;
            type = nightPool[sel];
        } else {
            // day pool: crab (weighted), seagull, dolphin, whale.
            var dayPool = [CR_CRAB, CR_SEAGULL, CR_DOLPHIN, CR_WHALE] as Array<Number>;
            type = dayPool[sel];
        }
        return [type, dir, frac, period] as Array;
    }

    // Water critters breach from the sea (drawn between the wave layers); the
    // others walk/fly along the shore (drawn in front of the beach).
    private function isWaterCritter(type as Number) as Boolean {
        return type == CR_DOLPHIN || type == CR_WHALE;
    }

    // Draw the active critter, positioning it for its type.
    private function drawCritter(dc as Dc, crit as Array) as Void {
        var w = mWidth;
        var h = mHeight;
        var type = crit[0] as Number;
        var dir = crit[1] as Number;
        var frac = crit[2] as Float;
        var seed = crit[3] as Number;

        var margin = (w * 0.18).toNumber();
        var span = w + 2 * margin;
        var x;
        if (dir == 1) {
            x = (-margin + frac * span).toNumber();
        } else {
            x = (w + margin - frac * span).toNumber();
        }

        if (type == CR_CRAB) {
            var groundY = (h * 0.93).toNumber();
            drawCrab(dc, x, groundY, dir, frac, (w * 0.04).toNumber());
        } else if (type == CR_SEAGULL) {
            // sky -> beach -> sky: glide down, walk a few steps, then take off.
            var skyY = (h * 0.30).toNumber();
            var beachWalkY = (h * 0.90).toNumber();
            var walking = false;
            var y;
            if (frac < 0.35) {
                y = (skyY + (beachWalkY - skyY) * (frac / 0.35)).toNumber();
            } else if (frac < 0.65) {
                y = beachWalkY;
                walking = true;
            } else {
                y = (beachWalkY + (skyY - beachWalkY) * ((frac - 0.65) / 0.35)).toNumber();
            }
            drawSeagull(dc, x, y, dir, frac, walking, (w * 0.05).toNumber());
        } else if (type == CR_DOLPHIN) {
            var waterY = (h * 0.79).toNumber();
            var leapH = (h * 0.18).toNumber();
            var y = (waterY - leapH * Math.sin(frac * Math.PI)).toNumber();
            drawDolphin(dc, x, y, dir, (frac < 0.5), (w * 0.06).toNumber());
        } else if (type == CR_WHALE) {
            var waterY = (h * 0.80).toNumber();
            var breachH = (h * 0.24).toNumber();
            var y = (waterY - breachH * Math.sin(frac * Math.PI)).toNumber();
            drawWhale(dc, x, y, dir, frac, (w * 0.11).toNumber());
        }
    }

    // Shear mapping used by the sea creatures: body space (bx = forward toward
    // the travel direction, by = up) -> screen, with a vertical `tilt` shear so
    // the body can lean nose-up/down as it arcs out of the water.
    private function crX(x as Number, dir as Number, bx as Float) as Number {
        return (x + dir * bx).toNumber();
    }
    private function crY(y as Number, bx as Float, by as Float, tilt as Float) as Number {
        return (y - by - tilt * bx).toNumber();
    }

    // ---- Crab (scuttles sideways across the sand) ----
    private function drawCrab(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 7) { s = 7; }
        var legPhase = frac * Math.PI * 18.0;  // fast scurry
        // black outline (4 diagonal offsets)
        crabSil(dc, x - 1, y - 1, dir, s, legPhase, 0x000000);
        crabSil(dc, x + 1, y - 1, dir, s, legPhase, 0x000000);
        crabSil(dc, x - 1, y + 1, dir, s, legPhase, 0x000000);
        crabSil(dc, x + 1, y + 1, dir, s, legPhase, 0x000000);
        // orange-red body
        crabSil(dc, x, y, dir, s, legPhase, 0xE2552E);
        // eyes on little stalks
        var ex1 = (x - s * 0.3).toNumber();
        var ex2 = (x + s * 0.3).toNumber();
        var stalkTop = (y - s * 0.95).toNumber();
        dc.setColor(0xE2552E, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(ex1, (y - s * 0.4).toNumber(), ex1, stalkTop);
        dc.drawLine(ex2, (y - s * 0.4).toNumber(), ex2, stalkTop);
        dc.setPenWidth(1);
        dc.setColor(0x201008, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(ex1, stalkTop, 2);
        dc.fillCircle(ex2, stalkTop, 2);
    }

    private function crabSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, legPhase as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // domed shell (wide oval)
        dc.fillRoundedRectangle((x - s).toNumber(), (y - s * 0.45).toNumber(), (2 * s).toNumber(), (s * 0.9).toNumber(), (s * 0.45).toNumber());
        dc.fillCircle(x, (y - s * 0.15).toNumber(), (s * 0.7).toNumber());
        // 3 legs per side, scurrying
        dc.setPenWidth(2);
        for (var i = 0; i < 3; i++) {
            var wob = (Math.sin(legPhase + i * 1.3) * s * 0.18).toNumber();
            var ly = (y + s * 0.1 + i * s * 0.28).toNumber();
            dc.drawLine((x - s * 0.6).toNumber(), ly, (x - s * 1.4).toNumber(), ly + wob);
            dc.drawLine((x + s * 0.6).toNumber(), ly, (x + s * 1.4).toNumber(), ly - wob);
        }
        dc.setPenWidth(1);
        // two raised claws (the larger one leads in the travel direction)
        dc.fillCircle((x + dir * s * 1.05).toNumber(), (y - s * 0.25).toNumber(), (s * 0.38).toNumber());
        dc.fillCircle((x - dir * s * 1.05).toNumber(), (y - s * 0.1).toNumber(), (s * 0.28).toNumber());
    }

    // ---- Seagull (flies in, lands and walks, then takes off) ----
    private function drawSeagull(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, walking as Boolean, s as Number) as Void {
        if (s < 8) { s = 8; }
        if (walking) {
            seagullWalk(dc, x, y, dir, frac, s);
        } else {
            seagullFly(dc, x, y, dir, Math.sin(frac * Math.PI * 9.0), s);
        }
    }

    private function seagullFly(dc as Dc, x as Number, y as Number, dir as Number, flap as Float, s as Number) as Void {
        var tipY = (y - flap * s * 0.7).toNumber();
        // body (white with a thin dark outline)
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 0.4).toNumber() + 1);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 0.4).toNumber());
        // head
        var hx = (x + dir * s * 0.5).toNumber();
        var hy = (y - s * 0.15).toNumber();
        dc.fillCircle(hx, hy, (s * 0.22).toNumber());
        // wings (grey, flapping)
        dc.setColor(0xD8DEE6, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x, (y - s * 0.1).toNumber()],
            [(x - s * 1.6).toNumber(), tipY],
            [(x - s * 0.5).toNumber(), (y + s * 0.2).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [x, (y - s * 0.1).toNumber()],
            [(x + s * 1.6).toNumber(), tipY],
            [(x + s * 0.5).toNumber(), (y + s * 0.2).toNumber()]
        ] as Array<Array>);
        // dark wing tips
        dc.setColor(0x3A3A42, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 1.6).toNumber(), tipY, 2);
        dc.fillCircle((x + s * 1.6).toNumber(), tipY, 2);
        // beak + eye
        dc.setColor(0xF2A024, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [(hx + dir * s * 0.15).toNumber(), (hy - 1).toNumber()],
            [(hx + dir * s * 0.55).toNumber(), (hy + s * 0.08).toNumber()],
            [(hx + dir * s * 0.15).toNumber(), (hy + s * 0.16).toNumber()]
        ] as Array<Array>);
        dc.setColor(0x201008, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((hx + dir * s * 0.05).toNumber(), (hy - 1).toNumber(), 1);
    }

    private function seagullWalk(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        // two thin legs, alternating as it steps
        var step = Math.sin(frac * Math.PI * 16.0) * s * 0.25;
        dc.setColor(0xF2A024, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine((x - s * 0.15).toNumber(), (y - s * 0.3).toNumber(), (x - s * 0.15 + step).toNumber(), (y + s * 0.4).toNumber());
        dc.drawLine((x + s * 0.15).toNumber(), (y - s * 0.3).toNumber(), (x + s * 0.15 - step).toNumber(), (y + s * 0.4).toNumber());
        dc.setPenWidth(1);
        // upright body (white, dark outline)
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, (y - s * 0.4).toNumber(), (s * 0.45).toNumber() + 1);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, (y - s * 0.4).toNumber(), (s * 0.45).toNumber());
        // folded grey wing
        dc.setColor(0xD8DEE6, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x - s * 0.25).toNumber(), (y - s * 0.55).toNumber(), (s * 0.7).toNumber(), (s * 0.42).toNumber(), 3);
        // head + beak + eye
        var hx = (x + dir * s * 0.35).toNumber();
        var hy = (y - s * 0.85).toNumber();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(hx, hy, (s * 0.25).toNumber());
        dc.setColor(0xF2A024, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [(hx + dir * s * 0.15).toNumber(), (hy - 1).toNumber()],
            [(hx + dir * s * 0.6).toNumber(), (hy + s * 0.08).toNumber()],
            [(hx + dir * s * 0.15).toNumber(), (hy + s * 0.18).toNumber()]
        ] as Array<Array>);
        dc.setColor(0x201008, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((hx + dir * s * 0.05).toNumber(), (hy - 1).toNumber(), 1);
    }

    // ---- Dolphin (leaps from the sea in a smooth arc) ----
    private function drawDolphin(dc as Dc, x as Number, y as Number, dir as Number, noseUp as Boolean, s as Number) as Void {
        if (s < 9) { s = 9; }
        var tilt = noseUp ? 0.5 : -0.5;
        // dark outline (slightly larger), then steel-grey body
        dolphinBody(dc, x, y, dir, tilt, (s * 1.12).toNumber(), 0x000000);
        dolphinBody(dc, x, y, dir, tilt, s, 0x5E7E8E);
        // pale belly + eye
        dc.setColor(0xCDE2EC, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(crX(x, dir, s * 0.2), crY(y, s * 0.2, -s * 0.3, tilt), (s * 0.3).toNumber());
        dc.setColor(0x10202A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(crX(x, dir, s * 1.0), crY(y, s * 1.0, s * 0.25, tilt), 2);
    }

    private function dolphinBody(dc as Dc, x as Number, y as Number, dir as Number, tilt as Float, s as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // main body: nose -> top back -> behind dorsal -> tail stalk -> belly -> chin
        dc.fillPolygon([
            [crX(x, dir, s * 1.7),  crY(y, s * 1.7,  s * 0.1,  tilt)],
            [crX(x, dir, s * 0.3),  crY(y, s * 0.3,  s * 0.55, tilt)],
            [crX(x, dir, -s * 0.6), crY(y, -s * 0.6, s * 0.45, tilt)],
            [crX(x, dir, -s * 1.5), crY(y, -s * 1.5, s * 0.2,  tilt)],
            [crX(x, dir, -s * 1.5), crY(y, -s * 1.5, -s * 0.15, tilt)],
            [crX(x, dir, -s * 0.3), crY(y, -s * 0.3, -s * 0.45, tilt)],
            [crX(x, dir, s * 1.1),  crY(y, s * 1.1,  -s * 0.3, tilt)]
        ] as Array<Array>);
        // dorsal fin
        dc.fillPolygon([
            [crX(x, dir, s * 0.1),  crY(y, s * 0.1,  s * 0.55, tilt)],
            [crX(x, dir, -s * 0.2), crY(y, -s * 0.2, s * 1.3,  tilt)],
            [crX(x, dir, -s * 0.6), crY(y, -s * 0.6, s * 0.5,  tilt)]
        ] as Array<Array>);
        // tail fluke
        dc.fillPolygon([
            [crX(x, dir, -s * 1.4), crY(y, -s * 1.4, s * 0.05, tilt)],
            [crX(x, dir, -s * 2.1), crY(y, -s * 2.1, s * 0.5,  tilt)],
            [crX(x, dir, -s * 2.1), crY(y, -s * 2.1, -s * 0.5, tilt)]
        ] as Array<Array>);
    }

    // ---- Whale (breaches from the sea, nose-up, with a spout and splash) ----
    private function drawWhale(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 14) { s = 14; }
        var tilt = 0.8;  // strong nose-up breach
        // foam/splash at the waterline base
        dc.setColor(0xEAF4FA, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - dir * s * 0.6).toNumber(), (y + s * 0.2).toNumber(), (s * 0.5).toNumber());
        dc.fillCircle((x + dir * s * 0.3).toNumber(), (y + s * 0.3).toNumber(), (s * 0.4).toNumber());
        // body: dark outline then deep blue-grey
        whaleBody(dc, x, y, dir, tilt, (s * 1.08).toNumber(), 0x000000);
        whaleBody(dc, x, y, dir, tilt, s, 0x33586E);
        // pectoral flipper
        dc.setColor(0x223F50, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [crX(x, dir, s * 0.3), crY(y, s * 0.3, -s * 0.3, tilt)],
            [crX(x, dir, s * 1.0), crY(y, s * 1.0, -s * 1.4, tilt)],
            [crX(x, dir, s * 0.6), crY(y, s * 0.6, -s * 0.1, tilt)]
        ] as Array<Array>);
        // a couple of belly grooves
        dc.setColor(0x8FB0BE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 3; i++) {
            dc.drawLine(
                crX(x, dir, s * 1.3), crY(y, s * 1.3, -s * 0.4 - i * 2, tilt),
                crX(x, dir, s * 0.2), crY(y, s * 0.2, -s * 0.6 - i * 2, tilt));
        }
        // eye
        dc.setColor(0x0A1820, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(crX(x, dir, s * 1.15), crY(y, s * 1.15, s * 0.35, tilt), 2);
        // spout from the blowhole
        var bhX = crX(x, dir, s * 0.9);
        var bhY = crY(y, s * 0.9, s * 1.0, tilt);
        dc.setColor(0xEAF4FA, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(bhX, bhY, (bhX - dir * s * 0.2).toNumber(), (bhY - s * 0.9).toNumber());
        dc.drawLine(bhX, bhY, (bhX + dir * s * 0.1).toNumber(), (bhY - s * 1.0).toNumber());
        dc.drawLine(bhX, bhY, (bhX + dir * s * 0.4).toNumber(), (bhY - s * 0.8).toNumber());
        dc.setPenWidth(1);
        dc.fillCircle((bhX + dir * s * 0.1).toNumber(), (bhY - s * 1.05).toNumber(), 2);
    }

    private function whaleBody(dc as Dc, x as Number, y as Number, dir as Number, tilt as Float, s as Number, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // head top -> rostrum -> lower jaw -> belly -> tail underside -> tail top -> back
        dc.fillPolygon([
            [crX(x, dir, s * 1.4),  crY(y, s * 1.4,  s * 0.9,  tilt)],
            [crX(x, dir, s * 1.75), crY(y, s * 1.75, s * 0.15, tilt)],
            [crX(x, dir, s * 1.3),  crY(y, s * 1.3,  -s * 0.55, tilt)],
            [crX(x, dir, 0.0),      crY(y, 0.0,      -s * 0.7, tilt)],
            [crX(x, dir, -s * 1.6), crY(y, -s * 1.6, -s * 0.3, tilt)],
            [crX(x, dir, -s * 1.6), crY(y, -s * 1.6, s * 0.4,  tilt)],
            [crX(x, dir, -s * 0.3), crY(y, -s * 0.3, s * 0.95, tilt)]
        ] as Array<Array>);
        // tail fluke
        dc.fillPolygon([
            [crX(x, dir, -s * 1.5), crY(y, -s * 1.5, 0.0,      tilt)],
            [crX(x, dir, -s * 2.2), crY(y, -s * 2.2, s * 0.6,  tilt)],
            [crX(x, dir, -s * 2.2), crY(y, -s * 2.2, -s * 0.5, tilt)]
        ] as Array<Array>);
    }

    // ----------------------------------------------------------- Sun times

    // Recompute today's local sunrise/sunset from the watch's last-known
    // location. Cached per day; keeps the fixed summer fallback until a real
    // location fix is available, then stops recomputing for the day.
    private function updateSunTimes() as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var doy = dayOfYear(info.year, info.month, info.day);
        if (doy == mSunDay && mSunValid) { return; }
        if (doy != mSunDay) {
            mSunDay = doy;
            mSunrise = 6.0;
            mSunset = 18.0;
            mSunValid = false;
            mSunLastTry = -10000;  // new day: allow an immediate retry
        }

        // Not yet valid for today: a location fix (or a usable result) isn't
        // available. Throttle retries so we don't run the location lookup + the
        // heavy sunrise/sunset trig on every redraw while we wait.
        var nowSec = Time.now().value();
        if ((nowSec - mSunLastTry) < 60) { return; }
        mSunLastTry = nowSec;

        var loc = getLocationDeg();
        if (loc == null) { return; }
        var offset = System.getClockTime().timeZoneOffset.toFloat() / 3600.0;
        var sr = computeSunEvent(doy, loc[0], loc[1], offset, true);
        var ss = computeSunEvent(doy, loc[0], loc[1], offset, false);
        if (sr != null && ss != null && ss > sr) {
            mSunrise = sr;
            mSunset = ss;
            mSunValid = true;
        }
    }

    // Last-known location in degrees [lat, lon], or null. Prefers the activity
    // location, then the weather observation location - neither powers the GPS.
    private function getLocationDeg() as Array<Float> or Null {
        try {
            if (Toybox has :Activity) {
                var ai = Activity.getActivityInfo();
                if (ai != null && ai.currentLocation != null) {
                    var d = ai.currentLocation.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        try {
            if (Toybox has :Weather) {
                var cc = Weather.getCurrentConditions();
                if (cc != null && cc.observationLocationPosition != null) {
                    var d = cc.observationLocationPosition.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        return null;
    }

    // Standard sunrise/sunset algorithm (NOAA / Almanac). Returns local time in
    // hours (0-24) for the event, or null at extreme latitudes where the sun
    // does not rise/set on the given day.
    private function computeSunEvent(n as Number, lat as Float, lng as Float, offset as Float, sunrise as Boolean) as Float or Null {
        var ZENITH = 90.833;
        var D2R = Math.PI / 180.0;
        var R2D = 180.0 / Math.PI;

        var lngHour = lng / 15.0;
        var tt = sunrise ? (n + ((6.0 - lngHour) / 24.0)) : (n + ((18.0 - lngHour) / 24.0));

        var m = (0.9856 * tt) - 3.289;
        var l = m + (1.916 * Math.sin(m * D2R)) + (0.020 * Math.sin(2.0 * m * D2R)) + 282.634;
        l = normDeg(l);

        var ra = Math.atan(0.91764 * Math.tan(l * D2R)) * R2D;
        ra = normDeg(ra);
        var lQuad = (Math.floor(l / 90.0) * 90.0).toFloat();
        var raQuad = (Math.floor(ra / 90.0) * 90.0).toFloat();
        ra = ra + (lQuad - raQuad);
        ra = ra / 15.0;

        var sinDec = 0.39782 * Math.sin(l * D2R);
        var cosDec = Math.cos(Math.asin(sinDec));

        var cosH = (Math.cos(ZENITH * D2R) - (sinDec * Math.sin(lat * D2R))) / (cosDec * Math.cos(lat * D2R));
        if (cosH > 1.0 || cosH < -1.0) { return null; }

        var bigH = sunrise ? (360.0 - (Math.acos(cosH) * R2D)) : (Math.acos(cosH) * R2D);
        bigH = bigH / 15.0;

        var bigT = bigH + ra - (0.06571 * tt) - 6.622;
        var ut = normHour(bigT - lngHour);
        return normHour(ut + offset);
    }

    private function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334] as Array<Number>;
        var n = cum[month - 1] + day;
        if (month > 2 && isLeapYear(year)) { n += 1; }
        return n;
    }

    private function isLeapYear(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    // NOTE: these use bounded modulo arithmetic rather than `while` loops. A
    // non-finite input (NaN/Infinity) from the sun math would make a subtract-
    // in-a-loop spin forever and hang the watch face; modulo can never loop.
    private function normDeg(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
        var r = a - 360.0 * Math.floor(a / 360.0);
        if (r < 0.0) { r += 360.0; }
        if (r >= 360.0) { r -= 360.0; }
        return r;
    }

    private function normHour(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
        var r = a - 24.0 * Math.floor(a / 24.0);
        if (r < 0.0) { r += 24.0; }
        if (r >= 24.0) { r -= 24.0; }
        return r;
    }

    // ------------------------------------------------------------ Color helpers

    function chordHalf(r as Number, dy as Number) as Number {
        var d = r * r - dy * dy;
        if (d <= 0) { return 0; }
        return Math.sqrt(d).toNumber();
    }

    function lerpColor(c1 as Number, c2 as Number, t as Float) as Number {
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }
        var r1 = (c1 >> 16) & 0xFF;
        var g1 = (c1 >> 8) & 0xFF;
        var b1 = c1 & 0xFF;
        var r2 = (c2 >> 16) & 0xFF;
        var g2 = (c2 >> 8) & 0xFF;
        var b2 = c2 & 0xFF;
        var r = (r1 + ((r2 - r1) * t)).toNumber();
        var g = (g1 + ((g2 - g1) * t)).toNumber();
        var b = (b1 + ((b2 - b1) * t)).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    function scaleColor(c as Number, f as Float) as Number {
        return lerpColor(0x000000, c, f);
    }

    // Smoothly calculate sky colors based on hour of day. When the day is
    // "normal", the gradient keyframes are anchored to the real sunrise/sunset
    // so dawn pastels, midday azure, and the marigold sunset land at the true
    // times; otherwise it falls back to a fixed summer schedule.
    private function getSkyColors(hour as Number, min as Number) as Array<Number> {
        var t = hour.toFloat() + min.toFloat() / 60.0;

        var sr = mSunrise;
        var ss = mSunset;
        var hours;

        // The keyframe colors are identical for both schedules; only the hour
        // anchors differ, so reuse the hoisted color tables and avoid rebuilding
        // three nine-element arrays on every frame.
        if (sr > 1.6 && ss < 22.4 && (ss - sr) > 4.0) {
            var mid = (sr + ss) / 2.0;
            hours = [0.0, sr - 1.5, sr, sr + 1.5, mid, ss - 1.5, ss, ss + 1.5, 24.0];
        } else {
            hours = SKY_HOURS_FALLBACK;
        }
        var topColors    = SKY_TOP;
        var bottomColors = SKY_BOTTOM;

        var idx = 0;
        for (var i = 0; i < hours.size() - 1; i++) {
            if (t >= hours[i] && t < hours[i+1]) {
                idx = i;
                break;
            }
        }

        var frac = (t - hours[idx]) / (hours[idx+1] - hours[idx]);
        var cTop = lerpColor(topColors[idx], topColors[idx+1], frac);
        var cBottom = lerpColor(bottomColors[idx], bottomColors[idx+1], frac);

        return [cTop, cBottom] as Array<Number>;
    }

    // Cached AMOLED sky gradient. Returns a buffered bitmap of the gradient, or
    // null if buffered bitmaps aren't available / couldn't be allocated (the
    // caller then renders the gradient directly). The expensive per-row fill loop
    // only runs when the colors or dimensions change (≈once per minute) or when
    // the graphics pool has reclaimed the previous buffer.
    private function getSkyBitmap(w as Number, skyH as Number, cTop as Number, cBottom as Number) as Graphics.BufferedBitmap or Null {
        if (!(Graphics has :createBufferedBitmap)) { return null; }

        var bmp = (mSkyBufRef != null) ? mSkyBufRef.get() : null;
        if (bmp != null && cTop == mSkyKeyTop && cBottom == mSkyKeyBottom && w == mSkyKeyW && skyH == mSkyKeyH) {
            return bmp;  // cache hit
        }

        try {
            var ref = Graphics.createBufferedBitmap({ :width => w, :height => skyH });
            if (ref == null) { return null; }
            mSkyBufRef = ref;
            bmp = ref.get();
            if (bmp == null) { return null; }

            var bdc = bmp.getDc();
            var step = 4;
            for (var y = 0; y < skyH; y += step) {
                var frac = y.toFloat() / skyH.toFloat();
                var c = lerpColor(cTop, cBottom, frac);
                bdc.setColor(c, Graphics.COLOR_TRANSPARENT);
                bdc.fillRectangle(0, y, w, step);
            }

            mSkyKeyTop = cTop;
            mSkyKeyBottom = cBottom;
            mSkyKeyW = w;
            mSkyKeyH = skyH;
            return bmp;
        } catch (e) {
            mSkyBufRef = null;
            return null;
        }
    }

    // ----------------------------------------------------------- Lifecycle

    function onHide() as Void {}

    function onExitSleep() as Void {
        mIsSleep = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        mIsSleep = true;
        mLastMin = -1;
        WatchUi.requestUpdate();
    }

    private function getWeatherString() as String or Null {
        try {
            if (Toybox has :Weather) {
                var conditions = Weather.getCurrentConditions();
                if (conditions != null && conditions.temperature != null) {
                    var temp = conditions.temperature;
                    var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
                    var isImperial = (settings has :temperatureUnits) && (settings.temperatureUnits != System.UNIT_METRIC);
                    if (isImperial) {
                        temp = (temp * 9.0 / 5.0 + 32.0).toNumber();
                        return temp.format("%d") + "°F";
                    } else {
                        return temp.format("%d") + "°C";
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    private function drawTextWithOutline(dc as Dc, x as Number, y as Number, font as Graphics.FontType, text as String, justify as Number, textColor as Number) as Void {
        if (mLowPower) {
            dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, text, justify);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y - 1, font, text, justify);
        dc.drawText(x + 1, y - 1, font, text, justify);
        dc.drawText(x - 1, y + 1, font, text, justify);
        dc.drawText(x + 1, y + 1, font, text, justify);
        dc.drawText(x - 1, y,     font, text, justify);
        dc.drawText(x + 1, y,     font, text, justify);
        dc.drawText(x,     y - 1, font, text, justify);
        dc.drawText(x,     y + 1, font, text, justify);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    private function drawHeartIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawHeartShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x - 1, y - 1);
        drawHeartShape(dc, x + 1, y - 1);
        drawHeartShape(dc, x - 1, y + 1);
        drawHeartShape(dc, x + 1, y + 1);
        drawHeartShape(dc, x - 1, y);
        drawHeartShape(dc, x + 1, y);
        drawHeartShape(dc, x,     y - 1);
        drawHeartShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x, y);
    }

    private function drawHeartShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillCircle(x - 4, y - 3, 4);
        dc.fillCircle(x + 4, y - 3, 4);
        dc.fillPolygon([[x - 8, y - 3], [x + 8, y - 3], [x, y + 7]] as Array<Array>);
    }

    // Battery icon: a horizontal cell with a terminal nub and a fill bar whose
    // width tracks the live charge level (0-100). A black halo behind it keeps
    // the outline legible against the moving backdrop, matching the heart icon.
    private function drawBatteryIcon(dc as Dc, x as Number, y as Number, color as Number, level as Number) as Void {
        var bw = 14;
        var bh = 9;
        var left = x - bw / 2;
        var top = y - bh / 2;

        var lvl = level;
        if (lvl < 0) { lvl = 0; }
        if (lvl > 100) { lvl = 100; }

        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(left, top, bw, bh, 2);
            dc.fillRectangle(left + bw, y - 2, 2, 4);
            return;
        }

        // Black halo backing (shell + nub) for legibility.
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(left - 1, top - 1, bw + 2, bh + 2, 3);
        dc.fillRectangle(left + bw, y - 3, 4, 6);

        // Battery shell + terminal nub.
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(left, top, bw, bh, 2);
        dc.fillRectangle(left + bw, y - 2, 2, 4);

        // Inner fill bar proportional to the charge level.
        var innerMax = bw - 4;
        var fillW = (innerMax * lvl / 100).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 2, top + 2, fillW, bh - 4);
        }
    }

    // Low-power partial update, called up to once per second in sleep mode.
    //
    // This MUST stay cheap: onPartialUpdate runs under a strict execution-time /
    // power budget, and exceeding it repeatedly makes the system disable partial
    // updates (the face "freezes" in always-on). The old implementation called
    // the full onUpdate() here, clearing and re-rendering the ENTIRE screen,
    // which is exactly what the budget forbids.
    //
    // The always-on layer shows no seconds, so nothing changes sub-minute. We
    // therefore redraw only when the minute rolls over, clip to the central
    // time/date band, and clear + repaint just that region.
    //
    // This cheap clipped path is ONLY safe on AMOLED always-on (burn-in) mode.
    // On MIP devices the sleep frame is the full colour scene, so clipping +
    // clearing a band here would paint a black rectangle over it; in that case
    // we fall back to the original full redraw.
    function onPartialUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        var min = clock.min;
        if (min == mLastMin) { return; }
        mLastMin = min;
        mClock = clock;

        var settings = System.getDeviceSettings();
        mSettings = settings;  // cache for drawTime / getWeatherString this frame
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        var aod = hasBurnIn && mIsSleep;

        // Not AMOLED always-on (or no clip support): preserve the original
        // full-scene minute refresh.
        if (!aod || !(dc has :setClip)) {
            onUpdate(dc);
            return;
        }

        mLowPower = true;

        // Match the anti-burn-in pixel shift used by the full minute redraw.
        var shift = computeBurnInShift();
        var cx = mCenterX + shift[0];
        var cy = mCenterY + shift[1];

        // Clip to the central time/date band so the clear + redraw is bounded to
        // a small region instead of the whole display.
        var clipY = (mHeight * 0.30).toNumber();
        var clipH = (mHeight * 0.34).toNumber();
        if (dc has :setClip) { dc.setClip(0, clipY, mWidth, clipH); }

        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        drawTime(dc, cx, cy - (mHeight * 0.05).toNumber());
        if (mShowDate) {
            drawDate(dc, cx, cy + (mHeight * 0.06).toNumber());
        }

        if (dc has :clearClip) { dc.clearClip(); }
    }
}
