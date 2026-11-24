// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#pragma once

// What GetSystemPowerStatus (and the Apple scaffold) report, before it is
// turned into the addon's PowerSource / battery-saver values. No Godot and
// no platform headers, so the host test can compile it.

struct RawSystemPower {
	bool valid = false;
	// 0 offline, 1 online, 255 unknown. Any other value is treated as unknown.
	int ac_line = 255;
	// SYSTEM_POWER_STATUS.BatteryFlag. Bit 128 means no battery. 255 means
	// the battery status itself is unknown.
	int battery_flag = 255;
	// SYSTEM_POWER_STATUS.SystemStatusFlag. Bit 0 is battery saver.
	int saver_flag = 0;
};

struct PowerReading {
	// DevicePower.PowerSource: -1 unknown, 0 battery, 1 external.
	int source = -1;
	// -1 unknown, 0 off, 1 on. A failed read is unknown; a successful read
	// is always off or on, because the flag is part of the same struct.
	int saver = -1;
};

PowerReading interpret_system_power(RawSystemPower in);
