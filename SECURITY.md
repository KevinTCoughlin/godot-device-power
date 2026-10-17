# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |
| < 0.1 | No |

Until 1.0, only the latest minor release receives security fixes.

## Reporting a vulnerability

**Do not open a public issue.**

Report privately through GitHub's
[private vulnerability reporting](https://github.com/KevinTCoughlin/godot-device-power/security/advisories/new)
for this repository. If that is unavailable to you, contact the maintainer
through their GitHub profile at <https://github.com/KevinTCoughlin>.

Please include:

- what an attacker can achieve, and what access they need to start;
- affected version, device, Android version and Godot version;
- a reproduction, ideally against the demo project.

You can expect an acknowledgement within 5 working days and an assessment within
15. Fixes are released as soon as they are ready; a GitHub Security Advisory is
published with credit to the reporter unless you ask otherwise. Please give a
reasonable disclosure window (90 days is the default) and tell us if the issue
is already public or under embargo elsewhere.

## Threat model

The addon reads device state and asks the display for a frame rate. It has no
network access, stores nothing, and handles no user data, so the interesting
boundaries are what it adds to an app and what game code can make it do.

Design properties that are intended to hold, and are therefore worth reporting
as bugs if they do not:

- **No permissions.** The Android plugin's manifest adds no
  `uses-permission`. The battery broadcast is sticky and protected, battery
  saver, thermal status and game mode are readable by any app, and
  `Surface.setFrameRate()` acts only on the app's own surface. A change that
  requires a permission is a security regression.
- **No exported components.** The broadcast receiver is registered at run
  time as not exported (`RECEIVER_NOT_EXPORTED` from Android 13), so other
  apps cannot send it intents; it only acts on protected system broadcasts.
- **No arbitrary Java invocation.** Game code reaches a fixed set of plugin
  methods with fixed argument types. The `JavaClassWrapper` fallback calls a
  fixed set of framework methods; no class or method name comes from game
  code.
- **Bounded input.** A frame rate vote that is not finite, negative or above
  1000 is refused before it reaches the platform.
- **A crash is a bug.** Malformed values from the platform read as "unknown";
  a value that makes the addon or a typed caller crash is worth reporting.

## Out of scope

- Vulnerabilities in Android, the device's firmware or the Godot engine.
  Report those upstream (though tell us if this addon makes one reachable that
  would not otherwise be).
- A game choosing a frame cap that drains the battery or heats the device.
  The policy is a recommendation; the game decides.
