# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## Shared setup for the DevicePowerAndroidBackend suites: the backend over
## fakes of the Java objects it reaches through AndroidRuntime
## (tests/fake_android.gd), at API 34 unless a test asks for another level.

const Facade := DevicePowerTestCase.FACADE_SCRIPT
const FakeAndroid := preload("res://tests/fake_android.gd")

var runtime: FakeAndroid.Runtime = null
var context: FakeAndroid.Context = null
var power_manager: FakeAndroid.PowerManager = null
var game_manager: FakeAndroid.GameManager = null
var battery: FakeAndroid.Intent = null
var display: FakeAndroid.Display = null
var backend: DevicePowerAndroidBackend = null


func before_each() -> void:
	super()
	power_manager = FakeAndroid.PowerManager.new()
	game_manager = FakeAndroid.GameManager.new()
	battery = FakeAndroid.Intent.new()
	context = FakeAndroid.Context.new()
	context.services = {"power": power_manager, "game": game_manager}
	context.battery = battery
	display = FakeAndroid.Display.new()
	display.current = FakeAndroid.Mode.new(60.0)
	display.modes = [display.current]
	var activity := FakeAndroid.Activity.new()
	activity.display = display
	runtime = FakeAndroid.Runtime.new()
	runtime.context = context
	runtime.activity = activity
	backend = _make_backend(34)


func after_each() -> void:
	super()
	backend = null
	runtime = null
	context = null
	power_manager = null
	game_manager = null
	battery = null
	display = null


## A backend over the fakes at API level [param sdk]. Off Android the wrapper
## cannot build the battery IntentFilter, so a stand-in is preset.
func _make_backend(sdk: int) -> DevicePowerAndroidBackend:
	var made := DevicePowerAndroidBackend.new(runtime)
	made._sdk = sdk
	made._filter = RefCounted.new()
	return made


func _rates(values: Array) -> PackedFloat32Array:
	return PackedFloat32Array(values)
