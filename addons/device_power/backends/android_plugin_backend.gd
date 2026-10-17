# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerAndroidPluginBackend
extends DevicePowerBackend

## Talks to the [code]DevicePowerAndroid[/code] engine singleton, the Kotlin
## plugin this addon's export plugin bundles into a Gradle build.
##
## The plugin listens for the platform's own change notifications (the
## battery and battery saver broadcasts, the thermal status listener) and
## re-reads the game mode on resume, so nothing is polled: its signals become
## [signal DevicePowerBackend.changed]. Getters return the plugin's last
## read, which costs no binder call.
##
## [b]Every value is checked.[/b] In a release export a script error makes
## the function return [code]null[/code] with no message, and a
## [code]null[/code] passed on into a typed native method can crash. So each
## answer is type-checked and range-checked here, and anything unexpected
## reads as "unknown".

## The singleton's name, from the plugin's manifest entry.
const SINGLETON_NAME := "DevicePowerAndroid"
## The plugin API this backend speaks (DevicePowerPlugin.API_VERSION).
const API_VERSION := 1
## The plugin's signals and how many arguments each carries. The arguments
## are not used: any signal means "read again".
const _SIGNALS := {
	&"power_changed": 2,
	&"game_mode_changed": 1,
	&"thermal_status_changed": 1,
	&"refresh_rates_changed": 0,
}

var _plugin: Object


func _init(plugin: Object) -> void:
	_plugin = plugin
	if not is_compatible():
		return
	for signal_name: StringName in _SIGNALS:
		if _plugin.has_signal(signal_name):
			var arity: int = _SIGNALS[signal_name]
			_plugin.connect(
				signal_name, _on_plugin_signal.unbind(arity) if arity > 0 else _on_plugin_signal
			)


## Whether [param plugin] is a plugin this backend can use: present, and
## reporting [constant API_VERSION].
func is_compatible() -> bool:
	return _int_or(_call_plugin("getApiVersion"), -1) == API_VERSION


func get_backend_name() -> String:
	return "android_plugin"


func pushes_changes() -> bool:
	return true


func request_update() -> void:
	if _plugin != null:
		_plugin.call("refresh")


func get_power_source() -> int:
	var source := _int_or(_call_plugin("getPowerSource"), -1)
	return source if source >= -1 and source <= 1 else -1


func is_power_saver_enabled() -> Variant:
	match _int_or(_call_plugin("getPowerSaver"), -1):
		0:
			return false
		1:
			return true
	return null


func get_game_mode() -> int:
	var mode := _int_or(_call_plugin("getGameMode"), 0)
	return mode if mode >= 0 and mode <= 4 else 0


func get_thermal_status() -> int:
	var status := _int_or(_call_plugin("getThermalStatus"), -1)
	return status if status >= -1 and status <= 6 else -1


func get_refresh_rates() -> PackedFloat32Array:
	var raw: Variant = _call_plugin("getRefreshRates")
	var rates := PackedFloat32Array()
	if not (raw is PackedFloat32Array or raw is PackedFloat64Array or raw is Array):
		return rates
	for rate: Variant in raw:
		if rate is float or rate is int:
			merge_refresh_rate(rates, rate)
	return rates


func vote_frame_rate(rate: float) -> bool:
	if _plugin == null or not is_finite(rate) or rate < 0.0:
		return false
	var made: Variant = _plugin.call("voteFrameRate", rate)
	# A JNI boolean arrives as a bool; JavaClassWrapper has been seen to hand
	# Java booleans back as ints, so accept either and nothing else.
	if made is bool:
		return made
	if made is int:
		return made != 0
	return false


## Calls a getter on the plugin. A missing method is a script error, which a
## release export turns into a [code]null[/code] return from this function
## alone; every caller treats [code]null[/code] as unknown.
func _call_plugin(method: StringName) -> Variant:
	if _plugin == null:
		return null
	return _plugin.call(method)


func _int_or(value: Variant, fallback: int) -> int:
	# Only a real int: a bool is not a status, and int == bool is a script error.
	return value if value is int else fallback


func _on_plugin_signal() -> void:
	changed.emit()
