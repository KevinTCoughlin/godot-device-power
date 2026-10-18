# Contributing

Thanks for considering a contribution to `godot-device-power`.

## Before you start

For anything larger than a bug fix, open an issue first. The API is deliberately
small: where the power comes from, what the OS and the device's temperature say
about it, and a frame cap built on those. A patch that turns the addon into a
general Android bridge, or adds a platform reading that no frame-cap decision
uses, will be declined however good the code is.

## Developer Certificate of Origin

Contributions are accepted under the [DCO](DCO.txt), not a CLA. Sign off every
commit:

```bash
git commit -s
```

which appends `Signed-off-by: Your Name <you@example.com>`. By signing off you
certify the DCO's terms. Commits without a sign-off cannot be merged. The
one exception is Dependabot's own version bumps, which it cannot sign off.

## Setting up

```bash
git clone https://github.com/KevinTCoughlin/godot-device-power.git
cd godot-device-power
./scripts/build_android.sh        # the Android plugin: needs JDK 21 and the Android SDK
```

Open the repository root as a Godot 4.7 project: it is both the demo project
and the test bed. The Kotlin plugin is a separate Gradle project in
`android-plugin/` (not `android/`, which Godot reserves for its Android build
template). Point Gradle at the SDK with `ANDROID_HOME` or an
`android-plugin/local.properties` holding `sdk.dir=...`.

## Before you open a pull request

Run all of it. CI runs the same things, and a red CI costs a review round.

```bash
./scripts/check.sh check          # all of the below, in order
```

which is:

```bash
./scripts/check.sh lint           # gdformat, gdlint, shellcheck, REUSE
./scripts/run_tests.sh            # the GDScript suite, mock- and fake-backed
./scripts/check.sh editor         # the editor loads the plugin without errors
./scripts/build_android.sh        # AARs, JVM unit tests, Android lint
```

`scripts/check.sh` runs every Python tool through `uvx` at a version pinned in
the script, so local results match CI exactly.

- **gdlint** reads `gdlintrc`; its deviations from the gdtoolkit defaults are
  explained there.
- **Android lint** treats warnings as errors (`android-plugin/plugin/build.gradle.kts`),
  so an unguarded API call fails the build rather than a device.
- **Kotlin** compiles with all warnings as errors.

### On a device

The suites cannot tell you what a phone does. If your change touches the
Android side, say in the pull request which devices and Android versions you
ran the demo on, and what you saw. **Do not claim a device check you did not
run**: "not tested on hardware" is a perfectly good pull request note, and a
false one is worse than none.

## House rules

- **Honest returns.** Unknown state is `null` or `-1`; a failed vote is
  `false`. Never substitute a plausible guess for an unknown value.
- **Check every value from Android.** In a release export a GDScript runtime
  error silently makes the function return `null`, and a `null` handed on to a
  typed native method can crash. Type-check and range-check whatever crosses
  the JNI boundary, and never compare across types (`int == bool` is a script
  error).
- **Keep the policy pure.** `fps_cap()`, `paced_cap()`,
  `thermal_back_off()` and `frame_rate_vote()` are static and side-effect
  free, so games can call them with their own state and tests need no device.
- **Every backend method has a mock.** A new reading needs a
  `DevicePowerBackend` method, a mock implementation, a fake-plugin method and
  tests.
- **Gate every Android API on its level.** The plugin's `minSdk` is Godot's
  (24); everything newer must degrade to "unknown".
- **Thread discipline in Kotlin.** Read the class comment in
  `DevicePowerPlugin.kt`: registration and platform reads happen on the main
  thread; Godot calls arrive on its render thread and must not block.
- **No build artefacts in commits.** No `.godot/`, no `build/`, no `*.aar`.

## Style

- **GDScript**: tabs, static types everywhere, `##` doc comments on public
  members, `_leading_underscore` for private members.
- **Kotlin**: the official code style (`kotlin.code.style=official`). Keep
  Android-framework calls in `DevicePowerPlugin.kt` thin and put decisions in
  `DevicePowerLogic.kt`, where JVM unit tests reach them.
- **Licensing**: every new file needs an SPDX header (a copyright line and an
  MIT license identifier, matching existing files) or an entry in
  `REUSE.toml` if the format cannot carry comments. `reuse lint` must pass.

## Reporting bugs

Use the issue templates. For an Android problem, include the device model,
Android version, whether the export used a Gradle build (which backend is
active: `DevicePower.get_backend_name()`), and `adb logcat -s DevicePower godot`
around the problem.

## Security

Do not open a public issue for a security problem; see
[`SECURITY.md`](SECURITY.md).
