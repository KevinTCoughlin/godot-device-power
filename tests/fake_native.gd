# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends RefCounted

## Stand-in for the DevicePowerNative GDExtension. Tests set the fields.

var supported: bool = true
var power_source: int = -1
var power_saver: Variant = null


func is_supported() -> bool:
	return supported


func get_power_source() -> int:
	return power_source


func is_power_saver_enabled() -> Variant:
	return power_saver
