// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class DevicePowerNative : public RefCounted {
	GDCLASS(DevicePowerNative, RefCounted);

protected:
	static void _bind_methods();

public:
	bool is_supported() const;
	int get_power_source() const;
	Variant is_power_saver_enabled() const;
};

} // namespace godot
