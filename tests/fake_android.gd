# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends RefCounted

## Fakes of the Java objects [DevicePowerAndroidBackend] reaches through
## [code]AndroidRuntime[/code], so the JavaClassWrapper backend runs on a
## desktop. Each fake answers only the calls the backend makes, with values
## a test sets; [code]null[/code] stands in for a Java null.
##
## [method JavaClassWrapper.get_exception] is always [code]null[/code] off
## Android, so these exercise every path except a thrown Java exception.
## [method JavaClassWrapper.wrap] is always [code]null[/code] there too: the
## SDK level reads as 0 (tests set [code]_sdk[/code]) and the battery intent
## filter must be preset (tests set [code]_filter[/code]).

# The fakes answer to Java's method names.
# gdlint: disable=function-name


## [code]AndroidRuntime[/code]: the application context and the activity.
class Runtime:
	extends RefCounted

	var context: Object = null
	var activity: Object = null
	var context_reads: int = 0

	func getApplicationContext() -> Object:
		context_reads += 1
		return context

	func getActivity() -> Object:
		return activity


## An application [code]Context[/code]: system services and the sticky
## battery broadcast.
class Context:
	extends RefCounted

	## Service name to service object.
	var services: Dictionary = {}
	## What [code]registerReceiver(null, filter)[/code] returns.
	var battery: Object = null
	var service_reads: Dictionary = {}
	var last_filter: Object = null

	func getSystemService(service_name: String) -> Object:
		service_reads[service_name] = int(service_reads.get(service_name, 0)) + 1
		return services.get(service_name)

	func registerReceiver(_receiver: Variant, filter: Object) -> Object:
		last_filter = filter
		return battery


## The sticky [code]ACTION_BATTERY_CHANGED[/code] intent.
class Intent:
	extends RefCounted

	## The [code]plugged[/code] extra, as the wrapper hands it back.
	var plugged: Variant = 0

	func getIntExtra(extra_name: String, fallback: int) -> Variant:
		return plugged if extra_name == "plugged" else fallback


## [code]PowerManager[/code]: battery saver and thermal status.
class PowerManager:
	extends RefCounted

	## The wrapper hands a Java boolean back as an int.
	var power_save: Variant = 0
	var thermal: Variant = 0

	func isPowerSaveMode() -> Variant:
		return power_save

	func getCurrentThermalStatus() -> Variant:
		return thermal


## [code]GameManager[/code] (API 31+).
class GameManager:
	extends RefCounted

	var mode: Variant = 0

	func getGameMode() -> Variant:
		return mode


## The activity: only its display is read.
class Activity:
	extends RefCounted

	var display: Object = null

	func getDisplay() -> Object:
		return display


## A [code]Display[/code]: its current mode and every mode it supports.
class Display:
	extends RefCounted

	var current: Object = null
	var modes: Variant = []

	func getMode() -> Object:
		return current

	func getSupportedModes() -> Variant:
		return modes


## A [code]Display.Mode[/code].
class Mode:
	extends RefCounted

	var width: Variant = 1080
	var height: Variant = 2400
	var rate: Variant = 60.0
	## [code]getAlternativeRefreshRates()[/code] (API 31+).
	var alternatives: Variant = []

	func _init(
		mode_rate: Variant = 60.0, mode_width: Variant = 1080, mode_height: Variant = 2400
	) -> void:
		rate = mode_rate
		width = mode_width
		height = mode_height

	func getPhysicalWidth() -> Variant:
		return width

	func getPhysicalHeight() -> Variant:
		return height

	func getRefreshRate() -> Variant:
		return rate

	func getAlternativeRefreshRates() -> Variant:
		return alternatives

# gdlint: enable=function-name
