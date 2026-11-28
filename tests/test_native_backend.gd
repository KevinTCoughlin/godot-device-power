# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## The GDExtension backend, driven by a fake native object. The real library
## is optional; when it is loaded on Linux it reports unsupported and
## [method DevicePowerNativeBackend.from_runtime] stays null.

const Backend := preload("res://addons/device_power/backends/native_backend.gd")
const Fake := preload("res://tests/fake_native.gd")
const Facade := DevicePowerTestCase.FACADE_SCRIPT


func test_a_missing_extension_stays_on_the_null_backend() -> void:
	for os_name: String in ["Windows", "macOS", "iOS"]:
		var backend: DevicePowerBackend = Facade.select_backend(
			os_name, func(_name: String) -> Object: return null
		)
		assert_eq(backend.get_backend_name(), "null", os_name)
	# Linux CI may have loaded the library. It must not claim support there,
	# or a desktop without the Windows read would start capping.
	var runtime: DevicePowerNativeBackend = Backend.from_runtime()
	assert_true(runtime == null, "this machine's binary is not a supported power read")


func test_an_unsupported_native_is_declined() -> void:
	var fake: RefCounted = Fake.new()
	fake.supported = false
	assert_eq(_from(fake), null, "is_supported false")


func test_saver_on_a_charger_caps_like_battery() -> void:
	var fake: RefCounted = Fake.new()
	fake.power_source = 1
	fake.power_saver = true
	var backend := Backend.new(fake, func() -> float: return 120.0)
	assert_eq(backend.get_power_source(), Facade.PowerSource.EXTERNAL, "plugged in")
	assert_eq(backend.is_power_saver_enabled(), true, "saver")
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array([120.0]), "current rate")
	var facade := make_facade()
	facade.set_backend(backend)
	assert_eq(facade.recommended_fps_cap(120.0), 60, "saver beats the charger")
	assert_eq(facade.get_thermal_status(), Facade.ThermalStatus.UNKNOWN, "no thermal guess")
	facade.free()


func test_bad_native_values_are_unknown() -> void:
	var fake: RefCounted = Fake.new()
	fake.power_source = 9
	fake.power_saver = 1
	var backend := Backend.new(fake, func() -> Variant: return "120")
	assert_eq(backend.get_power_source(), -1, "out of range")
	assert_null(backend.is_power_saver_enabled(), "an int is not the bool the extension returns")
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "a string rate is dropped")
	fake.power_saver = null
	assert_null(backend.is_power_saver_enabled(), "null stays unknown")


func test_a_failed_read_keeps_the_last_good_value() -> void:
	var fake: RefCounted = Fake.new()
	fake.power_source = 0
	fake.power_saver = true
	var backend := Backend.new(fake, func() -> float: return 60.0)
	assert_eq(backend.get_power_source(), 0, "battery")
	assert_eq(backend.is_power_saver_enabled(), true, "saver on")
	fake.read_ok = false
	assert_eq(backend.get_power_source(), 0, "a failed read keeps battery")
	assert_eq(backend.is_power_saver_enabled(), true, "a failed read keeps the saver")
	for broken: Variant in [null, "valid", {}, {"valid": 1, "source": 1, "saver": false}]:
		fake.status_override = broken
		assert_eq(backend.get_power_source(), 0, "%s is a failed read" % [broken])
		assert_eq(backend.is_power_saver_enabled(), true, "%s keeps the saver" % [broken])
	fake.status_override = null
	fake.read_ok = true
	fake.power_source = 1
	fake.power_saver = false
	assert_eq(backend.get_power_source(), 1, "a good read replaces it")
	assert_eq(backend.is_power_saver_enabled(), false, "saver off")


func test_a_failed_first_read_is_unknown() -> void:
	var fake: RefCounted = Fake.new()
	fake.power_source = 0
	fake.power_saver = true
	fake.read_ok = false
	var backend := Backend.new(fake, func() -> float: return 60.0)
	assert_eq(backend.get_power_source(), -1, "nothing to keep")
	assert_null(backend.is_power_saver_enabled(), "nothing to keep")


func test_a_good_read_of_unknown_replaces_the_last_value() -> void:
	# A valid read can still say unknown: Windows reports an AC line of 255
	# on a machine with a battery. That is the platform's answer, not a
	# failure, so it is not hidden behind the last value.
	var fake: RefCounted = Fake.new()
	fake.power_source = 0
	fake.power_saver = true
	var backend := Backend.new(fake, func() -> float: return 60.0)
	assert_eq(backend.get_power_source(), 0, "battery")
	fake.power_source = -1
	fake.power_saver = null
	assert_eq(backend.get_power_source(), -1, "a reported unknown is a reading")
	assert_null(backend.is_power_saver_enabled(), "a reported unknown saver is a reading")
	fake.power_source = 0
	backend.get_power_source()
	fake.power_source = 9
	assert_eq(backend.get_power_source(), -1, "an out-of-range value is a reading")


func test_the_facade_keeps_a_cap_through_a_failed_poll() -> void:
	var fake: RefCounted = Fake.new()
	fake.power_source = 1
	fake.power_saver = true
	var facade := make_facade()
	facade.set_backend(Backend.new(fake, func() -> float: return 120.0))
	assert_eq(facade.recommended_fps_cap(120.0), 60, "saver caps")
	var changes := [0]
	facade.changed.connect(func() -> void: changes[0] += 1)
	fake.read_ok = false
	facade.refresh()
	assert_eq(facade.get_power_source(), Facade.PowerSource.EXTERNAL, "still plugged in")
	assert_eq(facade.is_power_saver_enabled(), true, "still saving")
	assert_eq(facade.recommended_fps_cap(120.0), 60, "the cap holds")
	assert_eq(changes[0], 0, "a failed read is not a change")
	facade.free()


func test_freeing_the_facade_releases_the_native_object() -> void:
	var fake: RefCounted = Fake.new()
	fake.power_source = 0
	fake.power_saver = true
	var backend := Backend.new(fake, func() -> float: return 60.0)
	var facade := make_facade()
	facade.set_backend(backend)
	assert_eq(backend.get_power_source(), 0, "battery before shutdown")
	facade.free()
	assert_eq(backend.get_power_source(), -1, "the extension object was dropped")
	assert_null(backend.is_power_saver_enabled(), "saver is unknown after release")
	backend.release()


func test_backend_name_follows_the_os() -> void:
	var backend := Backend.new(Fake.new(), func() -> float: return -1.0)
	var expected := "native"
	match OS.get_name():
		"Windows":
			expected = "windows"
		"macOS":
			expected = "macos"
		"iOS":
			expected = "ios"
	assert_eq(backend.get_backend_name(), expected, OS.get_name())


func _from(fake: Object) -> DevicePowerNativeBackend:
	var supported: Variant = fake.call(&"is_supported")
	if not (supported is bool) or not supported:
		return null
	return Backend.new(fake)
