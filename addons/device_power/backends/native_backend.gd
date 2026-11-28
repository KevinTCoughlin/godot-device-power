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
## the facade keeps the null backend.
##
## [b]A failed read keeps the last answer.[/b] Each read is the extension's
## [code]read_power_status()[/code], whose [code]valid[/code] is
## [code]false[/code] when the platform call failed (a failed
## [code]GetSystemPowerStatus[/code] on Windows). The power source and
## battery saver then stay what the last good read said, or unknown if there
## has been none. A good read that reports unknown, such as an AC line of
## 255 on a machine with a battery, is the platform's answer and replaces
## it, and so does a value out of range. An extension built before
## [code]read_power_status()[/code] existed is read through
## [code]get_power_source()[/code] and [code]is_power_saver_enabled()[/code],
## which cannot tell a failure from an unknown, so there a failure is
## unknown.
##
## Refresh rate is the current one from [DisplayServer], the same limit as
## Linux: other modes are invisible, and this addon cannot switch them. The
## frame-rate vote is not made.

var _native: Object
var _read_refresh_rate: Callable
## The last good read of each value, returned when a read fails.
var _power_source: int = -1
var _power_saver: Variant = null


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
	if not _native.has_method(&"read_power_status"):
		return _source_from(_native.call(&"get_power_source"))
	var status: Variant = _read_status()
	if status is Dictionary:
		_power_source = _source_from(status.get("source"))
	return _power_source


func is_power_saver_enabled() -> Variant:
	if not is_instance_valid(_native):
		return null
	if not _native.has_method(&"read_power_status"):
		return _saver_from(_native.call(&"is_power_saver_enabled"))
	var status: Variant = _read_status()
	if status is Dictionary:
		_power_saver = _saver_from(status.get("saver"))
	return _power_saver


func get_refresh_rates() -> PackedFloat32Array:
	var rates := PackedFloat32Array()
	var rate: Variant = _read_refresh_rate.call()
	if rate is float or rate is int:
		merge_refresh_rate(rates, float(rate))
	return rates


static func _screen_refresh_rate() -> float:
	return DisplayServer.screen_get_refresh_rate()


## One [code]read_power_status()[/code], or [code]null[/code] when the read
## failed: [code]valid[/code] is not [code]true[/code], or the answer is not
## a [Dictionary] at all.
func _read_status() -> Variant:
	var status: Variant = _native.call(&"read_power_status")
	if not status is Dictionary:
		return null
	var valid: Variant = status.get("valid")
	if not (valid is bool and valid):
		return null
	return status


static func _source_from(source: Variant) -> int:
	if source is int and source >= -1 and source <= 1:
		return source
	return -1


static func _saver_from(saver: Variant) -> Variant:
	return saver if saver is bool else null
