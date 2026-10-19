# Godot 4.8 beta 1 evaluation

Evaluated 2026-10-19 on Fedora 44 x86_64, branch `eval/godot-4.8-beta1` (from
`main` at affa409). Nothing here changes `main`, the `godotVersion` pin
(`4.7.2.stable`) or CI. The binding decision stays: production engine is 4.7.2.

Engine: official `Godot_v4.8-beta1_linux.x86_64` (4.8.beta1.official.4d10419ca)
and `godot-lib.4.8.beta1.template_release.aar` from the same release, both
SHA512 verified against the release's `SHA512-SUMS.txt`.

## Results

| Check | 4.7.2 (baseline) | 4.8 beta 1 |
|---|---|---|
| `scripts/check.sh tests` (GDScript suite) | 72/72 | 72/72 |
| `scripts/check.sh editor` (editor-load smoke) | pass | pass |
| `project.godot` rewritten by the editor | no | no |
| New warnings in editor `--verbose` log | — | none |
| Gradle `build` (Kotlin, `allWarningsAsErrors`, lint, JVM tests) | pass, 21 tests | pass, 21 tests, 0 warnings |

The single `WARNING: ... speaks another API; falling back.` in the suite's
output is a negative test and appears on both engines.

## Building against 4.8

`org.godotengine:godot` 4.8 beta 1 is not on Maven Central (newest there is
`4.7.2.stable`). The Gradle build was run with `compileOnly` pointed at the
release's `godot-lib` AAR (temporary, not committed); everything compiled and
passed with `--rerun-tasks`.

The plugin uses `Godot`, `GodotPlugin`, `SignalInfo` and `UsedByGodot`.
`javap` of the 4.7.2 and 4.8 beta 1 AARs shows no public API change in
`GodotPlugin`, `SignalInfo` or `UsedByGodot`; `Godot` only gains a synthetic
Kotlin accessor (`access$setImeAnimating$p`).

Loading the 4.7.2-built AAR inside a 4.8 Gradle export, on a device, is covered
by the Salt Line and racer evaluations (their `docs/godot-4.8-beta1-eval.md`).

## Conclusion

No changes are needed for 4.8 beta 1. Keep `godotVersion = "4.7.2.stable"`.
Recheck when `org.godotengine:godot` 4.8 reaches Maven Central (RC/stable).
