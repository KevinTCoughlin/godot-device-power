# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0 the public API may change in a minor release.

## [Unreleased]

## [0.1.0] - 2026-10-17

First version as a standalone project. The addon was written for, and first
shipped in, the author's game Salt Line; this release extracts it and adds the
Android plugin and thermal back-off.

### Added

- `DevicePower` autoload, installed by the **Device Power** editor plugin:
  power source, battery saver, Android Game Mode and refresh rates, and
  `recommended_fps_cap()` built on the pure, static `fps_cap()` and
  `paced_cap()` policy (from Salt Line).
- **Frame rate vote**: `Surface.setFrameRate()` on Godot's render surface,
  seamless-only, following `Engine.max_fps` (from Salt Line).
- **Thermal status and back-off.** `get_thermal_status()` (the
  `ThermalStatus` enum, in `PowerManager`'s numbering) and
  `get_thermal_back_off()`. `fps_cap()` takes a `thermal_status`: from
  Moderate the cap is at most `battery_fps`, from Severe at most
  `battery_mode_fps`, and heat wins over Performance game mode. The facade
  backs off at once and recovers after `thermal_cooldown` seconds (default 30)
  below the current level. The thresholds are a starting point to calibrate.
- **Thermal caps are paced down, other caps up.** `paced_cap_down()` paces a
  cap to the highest evenly shown rate at or below it; `paced_fps_cap()` rounds
  a power or game-mode cap up (`paced_cap()`, as before) and the thermal limit
  (`thermal_limit()`) down, and never exceeds the latter. On a fixed 90 Hz
  panel Moderate heat now gives 45 (Severe 30), while battery alone still
  gives 90; on 144 Hz Moderate gives 48. `recommended_fps_cap()` uses it.
- **`DevicePowerAndroid` Kotlin plugin** (Godot Android plugin v2, AAR), bundled
  into Gradle exports by an `EditorExportPlugin`: a broadcast receiver for
  `ACTION_BATTERY_CHANGED` and `ACTION_POWER_SAVE_MODE_CHANGED`, a thermal
  status listener (API 29+), the game mode re-read on resume (API 31+), refresh
  rates at the current resolution including alternative rates (API 31+), and the
  frame rate vote, kept and re-applied when the render surface is recreated.
  Changes arrive as signals; nothing is polled but an optional 30 s safety
  read (`safety_poll_interval`).
- `DevicePowerAndroidPluginBackend`, which type-checks and range-checks every
  value from the plugin. The `JavaClassWrapper` backend remains as the fallback
  when the plugin is not in the export, and now reads the thermal status too.
- `DevicePower.select_backend()`, a testable backend choice.
- Headless GDScript suite that fails any test during which a script or engine
  error is logged; JVM unit tests for the plugin's logic; an editor-load smoke
  test; demo project; CI and a draft-release workflow that attaches the addon
  with built AARs.

### Fixed before release

- The editor plugin adds the `DevicePower` autoload in `_enable_plugin()` and
  removes it in `_disable_plugin()`. Doing it on every editor start and quit
  made a game's headless Android export rewrite `project.godot`, stripping
  its comments and dropping the autoload line.
- The plugin's battery receiver updates only the power source on
  `ACTION_BATTERY_CHANGED`, which fires on every level, voltage and
  temperature tick.
- Refresh rates within half a hertz of each other count as one (a Pixel 10
  listed 120 Hz twice).

### Verified on devices

On a Pixel 10 (60/120 Hz), a Lenovo Tab TB336FU (90 Hz) and a Galaxy A16
(90 Hz as apps see it), all Android 16, inside a shipping game: 120/90/90 fps
on a charger, 60/90/90 on battery, 60/45/45 at Moderate heat, 30 at Severe;
live charger and heat changes reach the cap within about half a second, and
the frame rate vote survives the app going to the background.

[Unreleased]: https://github.com/KevinTCoughlin/godot-device-power/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/KevinTCoughlin/godot-device-power/releases/tag/v0.1.0
