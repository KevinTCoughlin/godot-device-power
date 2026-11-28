// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#pragma once

#include "power_status.h"

// The platform read. On Windows this is GetSystemPowerStatus. On Apple it is
// the scaffold in apple_power.mm, which is not built by CI. Everywhere else
// the read is unsupported and returns an invalid status.
//
// valid must be false only when the platform call itself failed: the addon
// keeps its last good value for that, and reports a valid read's unknown as
// unknown. An Apple read that replaces the scaffold must keep that split.

RawSystemPower read_platform_power();

// True when this binary contains a platform read we are willing to ship.
// The Linux build returns false so loading the library on a CI runner does
// not pretend to know the battery. The Apple scaffold also returns false
// until a macOS or iOS binary has actually been loaded in Godot.
bool platform_power_is_supported();
