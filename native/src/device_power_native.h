// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class DevicePowerNative : public RefCounted {
	GDCLASS(DevicePowerNative, RefCounted);

protected:
	static void _bind_methods();

public:
	bool is_supported() const;
	// One platform read: valid (false when the read failed), source and
	// saver. The addon uses this, because a failed read and a read that
	// reports "unknown" both have a source of -1 and only valid tells them
	// apart.
	Dictionary read_power_status() const;
	// Each a read of its own. A failed read is -1 or null here, the same as
	// the platform's own unknown. Kept for callers of the first version.
	int get_power_source() const;
	Variant is_power_saver_enabled() const;
};

} // namespace godot
