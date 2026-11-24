// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#include "platform_power.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

RawSystemPower read_platform_power() {
#if defined(_WIN32)
	SYSTEM_POWER_STATUS status = {};
	if (GetSystemPowerStatus(&status) == 0) {
		return {};
	}
	RawSystemPower out;
	out.valid = true;
	out.ac_line = status.ACLineStatus;
	out.battery_flag = status.BatteryFlag;
	// SystemStatusFlag is the battery-saver bit on Windows 8 and later. The
	// field is the byte immediately after BatteryFlag; older headers named
	// it Reserved1. Both layouts are the same struct.
	out.saver_flag = status.SystemStatusFlag;
	return out;
#else
	return {};
#endif
}

bool platform_power_is_supported() {
#if defined(_WIN32)
	return true;
#else
	return false;
#endif
}
