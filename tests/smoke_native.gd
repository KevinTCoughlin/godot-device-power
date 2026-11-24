# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends SceneTree

## Run after scripts/build_native.sh. The Linux library must load and refuse
## to report a power source. Not part of the default suite: without the
## installed library this fails on purpose.


func _initialize() -> void:
	if not ClassDB.class_exists(&"DevicePowerNative"):
		push_error("DevicePowerNative did not load")
		quit(1)
		return
	var native: Variant = ClassDB.instantiate(&"DevicePowerNative")
	if not native is Object or native == null:
		push_error("DevicePowerNative did not instantiate")
		quit(1)
		return
	if native.call(&"is_supported") != false:
		push_error("this binary reported power support; the Linux build must not")
		quit(1)
		return
	if native.call(&"get_power_source") != -1:
		push_error("an unsupported read returned a power source")
		quit(1)
		return
	if native.call(&"is_power_saver_enabled") != null:
		push_error("an unsupported read returned a battery saver")
		quit(1)
		return
	print("native smoke: loaded, unsupported on this OS")
	quit(0)
