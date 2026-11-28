# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends RefCounted

## Stand-in for the DevicePowerNative GDExtension. Tests set the fields.
## [member read_ok] false is a failed platform read: [method read_power_status]
## then answers as the extension does, [code]valid[/code] false with nothing
## known.

var supported: bool = true
var power_source: int = -1
var power_saver: Variant = null
var read_ok: bool = true
## Replaces the whole [method read_power_status] answer when set.
var status_override: Variant = null


func is_supported() -> bool:
	return supported


func read_power_status() -> Variant:
	if status_override != null:
		return status_override
	if not read_ok:
		return {"valid": false, "source": -1, "saver": null}
	return {"valid": true, "source": power_source, "saver": power_saver}


func get_power_source() -> int:
	return power_source if read_ok else -1


func is_power_saver_enabled() -> Variant:
	return power_saver if read_ok else null
