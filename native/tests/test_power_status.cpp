// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#include "power_status.h"

#include <cstdio>
#include <cstdlib>

namespace {

int g_failed = 0;

void expect(bool ok, const char *message) {
	if (!ok) {
		std::fprintf(stderr, "FAIL %s\n", message);
		g_failed += 1;
	}
}

RawSystemPower raw(bool valid, int ac, int battery, int saver) {
	RawSystemPower in;
	in.valid = valid;
	in.ac_line = ac;
	in.battery_flag = battery;
	in.saver_flag = saver;
	return in;
}

} // namespace

int main() {
	{
		const PowerReading failed = interpret_system_power(raw(false, 1, 8, 1));
		expect(failed.source == -1 && failed.saver == -1, "a failed call is unknown");
	}
	{
		const PowerReading plugged = interpret_system_power(raw(true, 1, 8, 0));
		expect(plugged.source == 1 && plugged.saver == 0, "charging on AC is external, saver off");
	}
	{
		// Charge limit: online, not charging, saver on.
		const PowerReading limited = interpret_system_power(raw(true, 1, 0, 1));
		expect(limited.source == 1 && limited.saver == 1, "plugged in with saver on");
	}
	{
		const PowerReading battery = interpret_system_power(raw(true, 0, 2, 0));
		expect(battery.source == 0 && battery.saver == 0, "AC offline is battery");
	}
	{
		const PowerReading desktop = interpret_system_power(raw(true, 255, 128, 0));
		expect(desktop.source == 1 && desktop.saver == 0, "no battery and unknown AC is external");
	}
	{
		const PowerReading unsure = interpret_system_power(raw(true, 255, 1, 0));
		expect(unsure.source == -1 && unsure.saver == 0, "unknown AC with a battery is unknown");
	}
	{
		const PowerReading flag = interpret_system_power(raw(true, 255, 255, 1));
		expect(flag.source == -1 && flag.saver == 1, "unknown battery status still reports saver");
	}
	{
		const PowerReading other = interpret_system_power(raw(true, 7, 128, 0));
		expect(other.source == 1, "an undocumented AC value with no battery is external");
	}
	{
		const PowerReading offline = interpret_system_power(raw(true, 0, 128, 1));
		expect(offline.source == 0 && offline.saver == 1, "AC offline wins over the no-battery bit");
	}

	if (g_failed != 0) {
		std::fprintf(stderr, "%d assertion(s) failed\n", g_failed);
		return EXIT_FAILURE;
	}
	std::puts("power status mapping: ok");
	return EXIT_SUCCESS;
}
