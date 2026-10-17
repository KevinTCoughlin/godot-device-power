# godot-device-power

A Godot 4 addon that tells a game where its power comes from, whether the
device is running hot, and what the player asked for in the OS's game mode,
and turns that into a frame cap and a display refresh request: full refresh
rate on a charger, a lower cap on battery or when hot, and the player's game
mode respected over the power source.

On Android it ships a small Kotlin plugin that listens for the platform's own
change notifications, so nothing is polled. Without the plugin (a non-Gradle
export) it falls back to reading the same state through `JavaClassWrapper`.
Everywhere else it reports "unknown", which imposes nothing.

- Repository: <https://github.com/KevinTCoughlin/godot-device-power>
- License: MIT (see [`LICENSE`](LICENSE))
- Status: 0.1.0, not yet released. See [What has been tested](#what-has-been-tested).

## Why

Android 15 introduced a default frame rate for games: a Pixel runs an app
classified as a game at 60 fps however fast its panel is, unless the app asks
for more ([godotengine/godot#104179](https://github.com/godotengine/godot/issues/104179)).
Godot 4.7.2 never asks. Asking is one call, `Surface.setFrameRate()`, but
asking for 120 fps all the time costs battery a player may not want to spend.
So the question a game actually has is "how fast should I draw *right now*",
and the answer depends on the charger, battery saver, the OS game mode, the
device's temperature and what the panel can pace evenly. This addon answers
that, in one place, with a policy you can read and replace.

## Requirements

- Godot 4.7 (4.7.2 is what CI and the device tests use).
- For the Android plugin: an Android export with **Use Gradle Build** on
  (Godot's Android build template installed), minSdk 24, as Godot's own.
  Without a Gradle build the addon still works on Android through the
  `JavaClassWrapper` fallback.

## Installation

### From a release archive

1. Download `godot-device-power-<version>.zip` from the
   [releases page](https://github.com/KevinTCoughlin/godot-device-power/releases)
   and verify it against the published `.sha256` file. Until an archive is
   published, use the source build below.
2. Extract its `addons/device_power` directory into your project's `addons/`.
   It contains the debug and release AARs in `bin/`.
3. Enable **Device Power** in *Project → Project Settings → Plugins*. The
   plugin installs the `DevicePower` autoload and registers the export plugin
   that bundles the AAR into Android exports.

### From source

```bash
git clone https://github.com/KevinTCoughlin/godot-device-power.git
cd godot-device-power
./scripts/build_android.sh     # JDK 21 and the Android SDK; writes addons/device_power/bin/
```

Then copy `addons/device_power` into your project and enable the plugin.

### Android export

- Turn on **Gradle Build → Use Gradle Build** in the Android export preset
  (*Project → Install Android Build Template* first). The export plugin hands
  Godot `bin/debug/device_power-debug.aar` or `bin/release/device_power-release.aar`
  and the AAR's manifest registers the `DevicePowerAndroid` singleton. If the
  AARs are missing the export warns and the fallback backend is used.
- Keep **Package → App Category** at *Game* (Godot's default). Game modes, and
  Android's game default frame rate, apply only to apps classified as games.
- To let players pick Performance or Battery in the Game Dashboard, declare
  them in a `game_mode_config` resource referenced from the manifest
  (`android.game_mode_config` meta-data, with `supportsPerformanceGameMode` /
  `supportsBatteryGameMode`). The addon does not add this for you: it is a
  promise about your game.

## Usage

```gdscript
func _ready() -> void:
    DevicePower.changed.connect(_apply_cap)
    _apply_cap()

func _apply_cap() -> void:
    var cap = DevicePower.recommended_fps_cap(DisplayServer.screen_get_refresh_rate())
    # Checked, not trusted: see "Release exports" below.
    if cap is int:
        Engine.max_fps = cap
```

Menus and other idle screens are the game's business: apply your own lower cap
on top (the tighter of the two wins). The display vote follows whatever
`Engine.max_fps` ends up being.

### API

| Member | What it is |
| --- | --- |
| `changed` | Emitted when anything below changes, and once when a backend is set. |
| `get_power_source() -> PowerSource` | `UNKNOWN` (-1), `BATTERY` (0), `EXTERNAL` (1). |
| `is_power_saver_enabled() -> Variant` | `true`, `false`, or `null` when unknown. |
| `get_game_mode() -> GameMode` | Android's `GameManager` modes: `UNSUPPORTED`, `STANDARD`, `PERFORMANCE`, `BATTERY`, `CUSTOM`. |
| `get_thermal_status() -> ThermalStatus` | `PowerManager`'s numbering: `NONE` 0 … `SHUTDOWN` 6, `UNKNOWN` -1. |
| `get_thermal_back_off() -> ThermalBackOff` | `NONE`, `MODERATE`, `SEVERE`, after the cool-down. |
| `get_refresh_rates()`, `get_peak_refresh_rate()` | What the panel can run at its current resolution. |
| `recommended_fps_cap(refresh_rate) -> int` | The policy below for the current state, paced to the panel. `0` is no cap. |
| `refresh()` | Read the backend now. |
| `get_backend_name()` | `android_plugin`, `android`, `null` or `mock`. |
| `set_backend(backend)` | Inject a backend (tests use `DevicePowerMockBackend`). |
| `fps_cap()`, `paced_cap()`, `thermal_back_off()`, `frame_rate_vote()`, `select_backend()` | The pure, static policy, usable with your own state. |

| Export | Default | Meaning |
| --- | --- | --- |
| `battery_fps` | 60 | Cap on battery or with battery saver; the most that Moderate heat allows. |
| `battery_mode_fps` | 30 | Cap in Battery game mode; the most that Severe heat allows. |
| `thermal_cooldown` | 30 s | How long the status must stay lower before the cap recovers. |
| `vote_frame_rate` | on | Ask the display for the rate the game runs at. |
| `poll_interval` | 2 s | Poll period for the `JavaClassWrapper` fallback. |
| `safety_poll_interval` | 30 s | Safety read of the plugin backend; `0` turns it off. |

## Policy

`fps_cap()` is a pure static function, so a game can call it with its own
state or replace it. Rows are in priority order; heat is applied last and only
ever lowers the cap.

| State | Cap |
| --- | --- |
| OS game mode Performance | the panel's peak refresh rate at the current resolution (at most 240) |
| OS game mode Battery | `battery_mode_fps` (30) |
| Battery saver on | `battery_fps` (60), even on a charger |
| On battery | `battery_fps` (60) |
| On external power | 0 (no cap: V-Sync and the display decide) |
| Unknown (no bridge) | 0 |
| **then** thermal status Moderate | at most `battery_fps` (60); an uncapped game gets 60 |
| **then** thermal status Severe or worse | at most `battery_mode_fps` (30) |

Heat wins over Performance mode: a player's request for smoothness does not
outrank a device that is throttling. Light throttling is left to the platform.

"External power" means plugged in (the battery broadcast's `plugged` extra is
non-zero), not that the battery is gaining charge: a weak port or a charge
limit still counts.

**Pacing.** Every cap is then paced to the panel (`paced_cap()`): rounded *up*
to the nearest rate the display can show evenly, either a rate it can switch
to or one divided by a whole number. On a 60/120 Hz phone the battery cap
stays 60; on a panel fixed at 90 Hz it becomes 90 (no saving, rather than an
uneven 60 or a halved 45); 72 on 144 Hz; Battery game mode's 30 stays 30 on
90 Hz. Rounding up is a deliberate choice: a cap should never cost more
smoothness than it asked for. One consequence: on a fixed 90 Hz panel,
Moderate heat (60) saves nothing, and only Severe (30) lowers the rate.

**Hysteresis.** The facade backs off as soon as the status rises, and recovers
only after the status has stayed below the current level for
`thermal_cooldown` seconds; it then steps down to the highest level seen
during that time. A status flickering at a boundary does not make the frame
rate flicker.

**Calibrate it.** The thresholds and the 30 s cool-down are a starting point,
not a measurement. Play your hottest scene on your target devices and adjust
`battery_fps`, `battery_mode_fps` and `thermal_cooldown`, or call `fps_cap()`
with your own numbers.

## Asking the display for a rate

With `vote_frame_rate` on, the addon asks the platform for the rate the game
actually runs at: `Engine.max_fps` when set, the panel's peak when it is 0. A
game that drops to 30 fps on menus lets the panel follow instead of holding it
at its peak. The vote follows a change of `Engine.max_fps` within a frame, and
is resent after the app resumes. The plugin also keeps the last rate and
re-applies it when Godot's render surface is recreated. A vote of 0 withdraws
the request.

## Android notes

Facts the design rests on, from testing on a Pixel 10, a Lenovo Tab
(TB336FU) and a Galaxy A16, all on Android 16:

- **The vote** is `Surface.setFrameRate(rate, FRAME_RATE_COMPATIBILITY_DEFAULT,
  CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS)` on Godot's render surface (Android 12+).
  It lifts Android 15+'s game default frame rate (60 on Pixels,
  `ro.surface_flinger.game_default_frame_rate_override`) while the app stays
  classified as a game: 120 fps on a Pixel 10 on USB power. Seamless-only, so
  a change mid-game never blanks the screen for a mode switch. The user's peak
  refresh rate setting (Smooth Display) still caps every app.
- **Power source** is the sticky `ACTION_BATTERY_CHANGED` broadcast's
  `plugged` extra, not `BatteryManager.isCharging()`, which turns false on a
  full or charge-limited battery still on the charger. It follows
  `adb shell dumpsys battery unplug` / `dumpsys battery reset`, so the battery
  path can be tested on a device that has to stay on USB.
- **Refresh rates** are the modes at the current resolution plus each mode's
  alternative refresh rates (Android 12+). Only what apps are told counts: a
  Galaxy A16's `dumpsys display` lists 60 as an alternative of its single
  90 Hz mode, but `Display.Mode.getAlternativeRefreshRates()` and
  `Display.getSupportedRefreshRates()` both give `[90]`. It is treated as fixed
  at 90 Hz, like the Lenovo tablet.
- **What 120 fps costs.** On a Pixel 10, 120 vs 60 fps drew 1841 vs 1714 mW
  (+7%; display +83 mW, GPU +56 mW), from Perfetto power rails, 4 runs each.
  Worth having on a charger; a reasonable default to give up on battery.
- **Game modes** need the app classified as a game and Android 12+.
- **Thermal status** is `PowerManager`'s (Android 10+): a listener in the
  plugin, a read every poll in the fallback.

| Device | Android | Panel as apps see it | Verified |
| --- | --- | --- | --- |
| Pixel 10 | 16 | 60 / 120 Hz | vote lifts the game default to 120 fps; 60 on battery; power numbers above |
| Lenovo Tab TB336FU | 16 | fixed 90 Hz | reports one rate; the reason a 60 cap is paced up to 90 |
| Galaxy A16 (SM-A166U1) | 16 | fixed 90 Hz (60 hidden from apps) | apps are told `[90]` by both display APIs |

## Backends

| Backend | When | How |
| --- | --- | --- |
| `DevicePowerAndroidPluginBackend` | Android, plugin in the export | The `DevicePowerAndroid` singleton's signals; getters are cached reads. |
| `DevicePowerAndroidBackend` | Android, no plugin | `JavaClassWrapper`, polled every `poll_interval`; game mode on resume and focus. |
| `DevicePowerNullBackend` | everything else | Everything unknown; the policy imposes nothing. |
| `DevicePowerMockBackend` | tests | Fields you set. |

The plugin (`android-plugin/`, Kotlin, Godot Android plugin v2) registers a
broadcast receiver for `ACTION_BATTERY_CHANGED` and
`ACTION_POWER_SAVE_MODE_CHANGED` and a thermal status listener while the app is
resumed, re-reads the game mode on resume and when the facade regains focus,
and emits `power_changed`, `game_mode_changed`, `thermal_status_changed` and
`refresh_rates_changed`. Registration and platform reads run on the main
thread; Godot's calls arrive on its render thread and only read a published
snapshot, so a game never waits on a system call. Everything degrades by API
level to "unknown".

The plugin's singleton is `DevicePowerAndroid`, not `DevicePower`, so it does
not collide with the autoload.

### Release exports

In a Godot release export, a GDScript runtime error makes the function it
happens in return `null`, with no message. A `null` handed on to a typed
native method can crash. So every value that crosses from Android is
type-checked and range-checked before use (Java booleans can arrive as ints
through `JavaClassWrapper`, and `int == bool` is itself a script error), and
the policy functions never compare across types. Check
`recommended_fps_cap()`'s result with `is int` in your own code for the same
reason.

## Testing

```bash
./scripts/run_tests.sh              # GDScript suite: policy, hysteresis, backends, fake plugin
./scripts/build_android.sh          # AARs, JVM unit tests, Android lint
./scripts/check.sh check            # all of it, plus lint, REUSE and an editor-load smoke test
```

The GDScript suite runs headlessly with no device: Android is a fake singleton
and time is a fake clock. A test during which any script or engine error is
logged fails, because a script error otherwise ends the test early and quietly.

On a device, run the demo (`demo/demo.tscn`), then plug and unplug a charger,
toggle battery saver, change the game mode from the Game Dashboard, or use
`adb shell dumpsys battery unplug` and `adb shell cmd thermalservice
override-status 3` to exercise the battery and thermal paths.

### What has been tested

- The policy, pacing and vote behaviour, and the `JavaClassWrapper` backend,
  on the three devices above, as part of a shipping game.
- The Kotlin plugin, the thermal back-off and the plugin backend: unit tests,
  the GDScript suite against a fake singleton, and a Gradle export of the demo
  (the AAR is merged and the singleton registered). **Not yet run on hardware.**

## Prior art

None of the Android facts here are new; the packaging is: a Godot addon with a
power-source policy, a pacing rule and a thermal back-off on top.

- [ballistica's Android game mode design notes](https://github.com/efroemling/ballistica/blob/main/docs/design/android-game-mode.md)
  describe the same `setFrameRate()` approach inside an engine.
- [godotengine/godot#104179](https://github.com/godotengine/godot/issues/104179):
  FPS locked to 60 on Android 15.
- [godotengine/godot-proposals#8692](https://github.com/godotengine/godot-proposals/issues/8692):
  a battery API for Godot.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Commits are signed off under the
[DCO](DCO.txt).

## License

MIT. See [`LICENSE`](LICENSE).
