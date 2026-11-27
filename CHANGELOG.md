# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0 the public API may change in a minor release.

## [Unreleased]

### Added

- CI uploads `godot-device-power-<version>.zip` and the Asset Library zip
  (`scripts/package.sh`) as a build artifact. That job does not publish a
  release. The zip entry order and timestamps are pinned so the same commit
  and toolchain produce the same archives.
- A square Asset Library icon at `.github/store/icon.png`, also shipped as
  `addons/device_power/icon.png`.
- Linux, including Steam Deck, reports its power source from
  `/sys/class/power_supply` (`DevicePowerLinuxBackend`). Plugged in wins over
  the battery's status, so a charge limit stays external power. Battery
  saver, game mode and thermal status stay unknown, and the frame-rate vote
  is not made. Only the current refresh rate is known, and caps are paced as
  if the panel were fixed at that rate. The web stays on the null backend.
  Windows, macOS and iOS use the GDExtension when it is loaded and otherwise
  stay on the null backend.
- Releases carry signed SLSA build provenance for every archive (a
  `.sigstore.json` bundle; check with `gh attestation verify`).
- CodeQL scans the workflows and the Kotlin plugin on every pull request.
- Windows power source and battery saver from `GetSystemPowerStatus`, via an
  optional GDExtension (`DevicePowerNative`). The library is single precision,
  matching the official Godot 4.7 editor. If it is missing, or `is_supported`
  is false, Windows stays on the null backend. macOS (IOKit and Low Power
  Mode) and iOS (`UIDevice`, Low Power Mode) are scaffolded in
  `native/src/apple_power.mm` and are not compiled; Apple thermal states are
  not mapped onto Android's thermal enum. CI builds the Linux and Windows
  libraries and loads the Linux one in Godot.

### Fixed

- A failed Android refresh-rate read keeps the previous list. Resume, a
  battery-saver broadcast and `refresh()` published an empty list when the
  display was not ready or the read threw, which dropped the peak to 0 and
  made an uncapped game withdraw its frame-rate vote.
- Shutting down or freeing `DevicePower` releases the backend first. The
  Android plugin backend disconnects the engine singleton's signals in
  `release()`, and the native backend drops the GDExtension object, so a
  reload does not call into a freed object.
- `select_backend()` treats a missing Android singleton lookup as the null
  backend. An unknown OS name was already the null backend.
- The display vote is sent after `changed`. A handler that applies
  `recommended_fps_cap()` to `Engine.max_fps` is what gets voted on that
  update, including resume, instead of the previous cap.
- Polled backends re-read refresh rates on every poll. A rate change is
  noticed without a focus event, and float noise within half a hertz does
  not emit `changed`.
- The Android plugin reapplies a pending frame-rate vote when it attaches to
  a render surface that already exists. `SurfaceHolder.addCallback` does not
  deliver `surfaceCreated` in that case, so a vote that raced surface
  creation could sit unused until the next resume or the 30 s safety poll.

### Fixed

- The Android plugin registers a `DisplayManager.DisplayListener` while the
  app is resumed, and removes it on pause and on destroy. A refresh-rate
  change on the display the game is using updates the rate list immediately,
  instead of waiting for the next signal or the 30 s safety poll. On
  Android 16 (API 36) the listener subscribes to
  `EVENT_TYPE_DISPLAY_REFRESH_RATE`: the older two-argument registration no
  longer reports a refresh-rate change. Callbacks for other displays are
  ignored, and a failed read keeps the previous list.
- The demo scales its interface by screen density on phones and tablets. On
  a Pixel 10 it was drawn at desktop pixel size: text too small to read and
  a toggle too small to tap.

### Changed

- The README platform matrix covers Android, Linux, the Windows GDExtension,
  and the platforms that stay unknown (macOS and iOS until their scaffold is
  built, the web, and Windows when the extension is missing). Unknown is a
  normal result, not an error.
- The non-blocking Godot 4.8 preview in CI (headless suite and the
  `godot-lib` AAR compile check) now runs against 4.8-beta5 (commit
  `a661dfdbc`) instead of 4.8-beta4.

## [0.1.1] - 2026-11-04

### Added

- A `godot-device-power-<version>-asset-store.zip` release archive for the
  Godot Asset Store, rooted at `addons/` with `README.md` and `CHANGELOG.md`
  inside `addons/device_power/` beside its `LICENSE`.
- A 16:9 store thumbnail at `.github/store/thumbnail.png`, and `export-ignore`
  rules so GitHub's source zip ships only the addon.

### Changed

- Godot 4.8 beta 2 is covered as a preview, beside 4.7.2. CI runs the GDScript
  suite and the editor-load check on 4.8 beta 2 without failing the stable
  jobs, and compiles the Android plugin against that release's `godot-lib`
  AAR. The plugin is still built and shipped against `4.7.2.stable`. Device
  checks for 4.8 are listed in the README and have not been run.

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

[Unreleased]: https://github.com/KevinTCoughlin/godot-device-power/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/KevinTCoughlin/godot-device-power/releases/tag/v0.1.1
[0.1.0]: https://github.com/KevinTCoughlin/godot-device-power/releases/tag/v0.1.0
