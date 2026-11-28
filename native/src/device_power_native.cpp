// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#include "device_power_native.h"

#include "platform_power.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void DevicePowerNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &DevicePowerNative::is_supported);
	ClassDB::bind_method(D_METHOD("read_power_status"), &DevicePowerNative::read_power_status);
	ClassDB::bind_method(D_METHOD("get_power_source"), &DevicePowerNative::get_power_source);
	ClassDB::bind_method(D_METHOD("is_power_saver_enabled"), &DevicePowerNative::is_power_saver_enabled);
}

bool DevicePowerNative::is_supported() const {
	return platform_power_is_supported();
}

namespace {

Variant saver_variant(int saver) {
	if (saver < 0) {
		return Variant();
	}
	return Variant(saver == 1);
}

} // namespace

Dictionary DevicePowerNative::read_power_status() const {
	const PowerReading reading = interpret_system_power(read_platform_power());
	Dictionary out;
	out["valid"] = reading.valid;
	out["source"] = reading.source;
	out["saver"] = saver_variant(reading.saver);
	return out;
}

int DevicePowerNative::get_power_source() const {
	return interpret_system_power(read_platform_power()).source;
}

Variant DevicePowerNative::is_power_saver_enabled() const {
	return saver_variant(interpret_system_power(read_platform_power()).saver);
}
