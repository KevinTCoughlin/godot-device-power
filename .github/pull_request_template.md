<!--
SPDX-FileCopyrightText: 2026 Kevin Coughlin

SPDX-License-Identifier: MIT
-->

## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- The problem being solved, not just the diff. -->

## Testing

- [ ] `./scripts/run_tests.sh` (GDScript suite)
- [ ] `./scripts/check.sh editor` (the editor loads the plugin)
- [ ] `./scripts/build_android.sh` (AARs, JVM unit tests, Android lint)
- [ ] `./scripts/check.sh lint` (gdformat, gdlint, shellcheck, REUSE)

### On devices

<!--
If this touches the Android side or the policy, say which devices and Android
versions you ran the demo on and what you saw. If you did not run any, say so:
"not tested on hardware" is a fine answer, a false claim is not.
-->

Devices / Android versions:
What you saw:

## Checklist

- [ ] Commits are signed off (`git commit -s`) per the [DCO](../DCO.txt)
- [ ] Unknown state is still reported honestly (`null` / `-1` / `false`)
- [ ] Every value from Android is type-checked before use
- [ ] New readings have a backend method, a mock, a fake-plugin method and tests
- [ ] New Android APIs are gated on their API level
- [ ] New files carry SPDX headers, or an entry in `REUSE.toml`
- [ ] `CHANGELOG.md` updated for a user-visible change
- [ ] No build artefacts committed (`.godot/`, `build/`, `*.aar`)
