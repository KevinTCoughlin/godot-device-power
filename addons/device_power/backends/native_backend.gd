# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerNativeBackend
extends DevicePowerBackend

## Power source and battery saver from the [code]DevicePowerNative[/code]
## GDExtension, on Windows today. macOS and iOS have a scaffold that does not
## report itself as supported, so they stay on [DevicePowerNullBackend].
##
## The extension is optional. If it is missing, built for another platform,
## or [method is_supported] is false, [method from_runtime] returns null and
## the facade keeps the null backend. A failed platform read is unknown, not
## a guess.
##
## Refresh rate is the current one from [DisplayServer], the same limit as
## Linux: other modes are invisible, and this addon cannot switch them. The
## frame-rate vote is not made.

var _native: Object
var _read_refresh_rate: Callable


func _init(native: Object, read_refresh_rate: Callable = Callable()) -> void:
	_native = native
	_read_refresh_rate = read_refresh_rate if read_refresh_rate.is_valid() else _screen_refresh_rate


## Drops the extension object. [DevicePower] calls this before it frees the
## backend, on shutdown and when a backend is replaced.
func release() -> void:
	_native = null


func get_backend_name() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"iOS":
			return "ios"
		_:
			return "native"


## The extension's backend when it is loaded and reports that this binary can
## read the platform, otherwise null.
static func from_runtime() -> DevicePowerNativeBackend:
	if not ClassDB.class_exists(&"DevicePowerNative"):
		return null
	var native: Variant = ClassDB.instantiate(&"DevicePowerNative")
	if not native is Object or native == null:
		return null
	var supported: Variant = native.call(&"is_supported")
	if not (supported is bool) or not supported:
		return null
	return DevicePowerNativeBackend.new(native)


func get_power_source() -> int:
	if not is_instance_valid(_native):
		return -1
	var source: Variant = _native.call(&"get_power_source")
	if source is int and source >= -1 and source <= 1:
		return source
	return -1


func is_power_saver_enabled() -> Variant:
	if not is_instance_valid(_native):
		return null
	var saver: Variant = _native.call(&"is_power_saver_enabled")
	if saver is bool:
		return saver
	return null


func get_refresh_rates() -> PackedFloat32Array:
	var rates := PackedFloat32Array()
	var rate: Variant = _read_refresh_rate.call()
	if rate is float or rate is int:
		merge_refresh_rate(rates, float(rate))
	return rates


static func _screen_refresh_rate() -> float:
	return DisplayServer.screen_get_refresh_rate()
