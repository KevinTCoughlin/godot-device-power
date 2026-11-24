// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

// Scaffold for macOS and iOS. CI does not compile this file, and
// platform_power_is_supported() stays false on Apple until that changes, so
// a binary built from it still falls back to the null backend.
//
// Not verified: this has not been compiled, linked, or loaded in Godot.
//
// Intended read, once it is built and checked on a machine:
//
// macOS (IOKit, no extra permission):
//   IOPSCopyPowerSourcesInfo / IOPSCopyPowerSourcesList /
//   IOPSGetPowerSourceDescription.
//   kIOPSPowerSourceStateKey is kIOPSACPowerValue or kIOPSBatteryPowerValue.
//   A state of AC is external power even when kIOPSIsChargingKey is false
//   (a charge limit). No power source at all is external (a desktop).
//   NSProcessInfo.processInfo.isLowPowerModeEnabled is the battery saver.
//
// iOS (UIKit):
//   UIDevice.current.batteryMonitoringEnabled = YES, then batteryState:
//   unplugged -> battery, charging or full -> external, unknown -> unknown.
//   NSProcessInfo.processInfo.isLowPowerModeEnabled is the battery saver.
//
// Thermal state (NSProcessInfo.thermalState: nominal / fair / serious /
// critical) is deliberately not mapped onto Android's ThermalStatus. The
// numbers are a different scale, and this addon does not guess one from the
// other. get_thermal_status() stays unknown on Apple.

#if defined(__APPLE__)
#include "platform_power.h"

RawSystemPower read_apple_power_scaffold() {
	// Replaced by the IOKit / UIDevice read described above. Returning an
	// invalid status keeps the addon on "unknown" if this file is linked
	// before that read exists.
	return {};
}
#endif
