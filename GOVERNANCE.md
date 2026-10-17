# Governance

`godot-device-power` is a small, single-maintainer project. This document says
who decides what, so contributors know what to expect rather than having to
guess.

## Roles

**Maintainer.** Kevin Coughlin ([@KevinTCoughlin](https://github.com/KevinTCoughlin))
is the current maintainer: final say on scope, API design and releases, and the
only person who can merge to `main` or publish a release.

**Contributors.** Anyone who opens an issue or pull request. No formal status is
required and none is conferred.

**Committers.** None beyond the maintainer today. If the project attracts
sustained contribution, contributors with a track record of merged, reviewed work
may be invited; the invitation and its acceptance are recorded in this file.

## How decisions are made

Ordinary changes (bug fixes, tests, documentation, a reading gated on its API
level) are decided in the pull request. One maintainer approval merges them.

Scope changes (a new platform, a change to the public API or the default
policy, a new dependency, or a new Android permission) start as an issue so the
discussion is public and searchable before code exists. The maintainer decides,
and writes down the reason in the issue and, where it shapes the project, in the
README or the changelog, including the ones that are a "no".

There is no voting. If a decision proves wrong, it gets revisited; being able to
point at the recorded reason is what makes that possible.

## What is not negotiable

Three properties are the reason this project exists, and a change that breaks one
will be declined regardless of its merits:

1. **Honest reporting.** An unknown value is never replaced by a guess, and a
   vote that was not made is never reported as made.
2. **No crash on bad input.** Whatever the platform returns, the addon reads
   it as a value or as "unknown"; it never hands a game a type it did not
   promise.
3. **No permissions.** The Android plugin adds none.

## Releases

The maintainer tags releases. A release requires: green CI, a
[`CHANGELOG.md`](CHANGELOG.md) entry, and, for anything touching the Android
side, the demo run on real devices, with the devices, Android versions and
results recorded in the release notes. A release never claims a check that was
not run.

## Code of conduct

Participation is governed by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). The
maintainer handles reports and enforcement.

## Succession

If the maintainer becomes unavailable for an extended period, the repository is
MIT-licensed: fork it. If you would like to take over the canonical repository
rather than fork, open an issue; if there is no response within 90 days, treat
the project as unmaintained and say so clearly in your fork.
