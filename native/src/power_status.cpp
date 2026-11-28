// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#include "power_status.h"

namespace {

constexpr int kSourceUnknown = -1;
constexpr int kSourceBattery = 0;
constexpr int kSourceExternal = 1;
constexpr int kSaverUnknown = -1;
constexpr int kSaverOff = 0;
constexpr int kSaverOn = 1;
constexpr int kNoBattery = 128;

} // namespace

PowerReading interpret_system_power(RawSystemPower in) {
	PowerReading out;
	if (!in.valid) {
		return out;
	}
	out.valid = true;
	out.saver = (in.saver_flag & 1) != 0 ? kSaverOn : kSaverOff;

	const bool no_battery = (in.battery_flag & kNoBattery) != 0 && in.battery_flag != 255;
	if (in.ac_line == 1) {
		// Plugged in, whether or not the pack is gaining charge.
		out.source = kSourceExternal;
	} else if (in.ac_line == 0) {
		out.source = kSourceBattery;
	} else if (no_battery) {
		// AC line unknown, and the machine reports no battery. A desktop.
		out.source = kSourceExternal;
	} else {
		out.source = kSourceUnknown;
	}
	return out;
}
