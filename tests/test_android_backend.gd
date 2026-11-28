# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends "res://tests/android_backend_case.gd"

## DevicePowerAndroidBackend, the JavaClassWrapper fallback: API-level
## gating, value checking, service caching, and the facade on top of it.


func test_identity() -> void:
	assert_eq(backend.get_backend_name(), "android")
	assert_false(backend.pushes_changes(), "the fallback is polled")
	assert_true(backend.can_vote_frame_rate(), "Surface.setFrameRate")


func test_the_sdk_level_is_unknown_off_android() -> void:
	var fresh := DevicePowerAndroidBackend.new(runtime)
	assert_eq(fresh._sdk, 0, "Build.VERSION cannot be wrapped here")
	assert_eq(fresh.get_game_mode(), 0, "API 31 gate")
	assert_eq(fresh.get_thermal_status(), -1, "API 29 gate")
	assert_eq(fresh.get_refresh_rates(), PackedFloat32Array(), "API 30 gate")
	assert_false(fresh.vote_frame_rate(60.0), "API 31 gate")


func test_everything_is_unknown_without_a_context() -> void:
	runtime.context = null
	runtime.activity = null
	assert_eq(backend.get_power_source(), -1, "power source")
	assert_null(backend.is_power_saver_enabled(), "saver")
	assert_eq(backend.get_game_mode(), 0, "game mode")
	assert_eq(backend.get_thermal_status(), -1, "thermal")
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "refresh rates")
	assert_false(backend.vote_frame_rate(60.0), "vote")


func test_a_context_found_later_is_used() -> void:
	runtime.context = null
	assert_eq(backend.get_thermal_status(), -1, "no context yet")
	runtime.context = context
	power_manager.thermal = 2
	assert_eq(backend.get_thermal_status(), 2, "the next read finds it")


func test_power_source_follows_the_plugged_extra() -> void:
	var cases := {0: 0, 1: 1, 2: 1, 4: 1, 8: 1}
	for plugged: int in cases:
		battery.plugged = plugged
		assert_eq(backend.get_power_source(), cases[plugged], "plugged=%d" % plugged)


func test_a_bad_battery_broadcast_is_unknown() -> void:
	for plugged: Variant in [-1, null, "1", 1.0]:
		battery.plugged = plugged
		assert_eq(backend.get_power_source(), -1, "plugged=%s" % [plugged])
	context.battery = null
	assert_eq(backend.get_power_source(), -1, "no sticky broadcast")


func test_the_battery_filter_is_built_once_and_reused() -> void:
	var filter: Object = backend._filter
	backend.get_power_source()
	backend.get_power_source()
	assert_true(context.last_filter == filter, "the cached filter is passed")


func test_without_a_filter_the_power_source_is_unknown() -> void:
	backend._filter = null
	battery.plugged = 1
	assert_eq(backend.get_power_source(), -1, "IntentFilter cannot be wrapped here")
	assert_null(backend._filter, "a failed build is not cached")


func test_the_saver_is_a_bool_whatever_the_wrapper_returns() -> void:
	var cases := [[1, true], [0, false], [true, true], [false, false]]
	for pair: Array in cases:
		power_manager.power_save = pair[0]
		assert_eq(backend.is_power_saver_enabled(), pair[1], "isPowerSaveMode=%s" % [pair[0]])
	for garbage: Variant in [null, "1", 1.0]:
		var fresh := _make_backend(34)
		power_manager.power_save = garbage
		assert_null(fresh.is_power_saver_enabled(), "first isPowerSaveMode=%s" % [garbage])


func test_a_missing_power_service_is_unknown() -> void:
	context.services.erase("power")
	assert_null(backend.is_power_saver_enabled(), "saver")
	assert_eq(backend.get_thermal_status(), -1, "thermal")


func test_services_are_fetched_once() -> void:
	backend.is_power_saver_enabled()
	backend.get_thermal_status()
	backend.is_power_saver_enabled()
	backend.get_game_mode()
	backend.get_game_mode()
	assert_eq(context.service_reads.get("power"), 1, "power fetched once")
	assert_eq(context.service_reads.get("game"), 1, "game fetched once")


func test_a_missing_service_is_fetched_again() -> void:
	context.services.erase("game")
	assert_eq(backend.get_game_mode(), 0, "missing")
	context.services["game"] = game_manager
	game_manager.mode = 2
	assert_eq(backend.get_game_mode(), 2, "found on a later read")


func test_game_mode_needs_api_31() -> void:
	game_manager.mode = 2
	var old := _make_backend(30)
	assert_eq(old.get_game_mode(), 0, "API 30")
	assert_false(context.service_reads.has("game"), "GameManager not asked for below API 31")
	assert_eq(_make_backend(31).get_game_mode(), 2, "API 31")


func test_game_mode_values() -> void:
	for mode: int in range(0, 5):
		game_manager.mode = mode
		assert_eq(backend.get_game_mode(), mode, "mode %d" % mode)
	for out_of_range: int in [-1, 5]:
		game_manager.mode = 2
		backend.get_game_mode()
		game_manager.mode = out_of_range
		assert_eq(backend.get_game_mode(), 0, "mode %d is Android's answer" % out_of_range)
	for garbage: Variant in [2.0, null, "2"]:
		game_manager.mode = garbage
		assert_eq(_make_backend(34).get_game_mode(), 0, "first mode %s" % [garbage])


func test_thermal_status_needs_api_29() -> void:
	power_manager.thermal = 3
	assert_eq(_make_backend(28).get_thermal_status(), -1, "API 28")
	assert_eq(_make_backend(29).get_thermal_status(), 3, "API 29")


func test_thermal_status_values() -> void:
	for status: int in range(0, 7):
		power_manager.thermal = status
		assert_eq(backend.get_thermal_status(), status, "status %d" % status)
	for out_of_range: int in [-1, 7]:
		power_manager.thermal = 3
		backend.get_thermal_status()
		power_manager.thermal = out_of_range
		assert_eq(backend.get_thermal_status(), -1, "status %d is Android's answer" % out_of_range)
	for garbage: Variant in [3.0, null, "3"]:
		power_manager.thermal = garbage
		assert_eq(_make_backend(34).get_thermal_status(), -1, "first status %s" % [garbage])


func test_a_failed_read_keeps_the_last_good_value() -> void:
	battery.plugged = 0
	power_manager.power_save = 1
	game_manager.mode = 3
	power_manager.thermal = 4
	assert_eq(backend.get_power_source(), 0, "battery")
	assert_eq(backend.is_power_saver_enabled(), true, "saver on")
	assert_eq(backend.get_game_mode(), 3, "battery mode")
	assert_eq(backend.get_thermal_status(), 4, "critical")
	battery.plugged = -1
	power_manager.power_save = null
	game_manager.mode = null
	power_manager.thermal = "4"
	assert_eq(backend.get_power_source(), 0, "a broadcast without plugged keeps battery")
	assert_eq(backend.is_power_saver_enabled(), true, "a Java null keeps the saver")
	assert_eq(backend.get_game_mode(), 3, "a Java null keeps the mode")
	assert_eq(backend.get_thermal_status(), 4, "garbage keeps the heat")
	context.battery = null
	assert_eq(backend.get_power_source(), 0, "no sticky broadcast keeps battery")
	runtime.context = null
	assert_eq(backend.get_power_source(), 0, "no context keeps battery")
	assert_eq(backend.get_thermal_status(), 4, "the cached service still answers")
	runtime.context = context
	context.battery = battery
	battery.plugged = 1
	power_manager.power_save = 0
	game_manager.mode = 1
	power_manager.thermal = 0
	assert_eq(backend.get_power_source(), 1, "a good read replaces it")
	assert_eq(backend.is_power_saver_enabled(), false, "saver off")
	assert_eq(backend.get_game_mode(), 1, "standard")
	assert_eq(backend.get_thermal_status(), 0, "cool")


func test_a_missing_service_keeps_the_last_good_value() -> void:
	power_manager.power_save = 1
	power_manager.thermal = 3
	var fresh := _make_backend(34)
	assert_eq(fresh.get_thermal_status(), 3, "read")
	assert_eq(fresh.is_power_saver_enabled(), true, "read")
	# Drop the cache, as if the service had never been fetched, and make the
	# next fetch fail.
	fresh._power_manager = null
	context.services.erase("power")
	assert_eq(fresh.get_thermal_status(), 3, "kept")
	assert_eq(fresh.is_power_saver_enabled(), true, "kept")


func test_the_facade_keeps_a_cap_through_a_failed_poll() -> void:
	battery.plugged = 0
	power_manager.thermal = 3
	power.set_backend(backend)
	assert_eq(power.recommended_fps_cap(120.0), 30, "severe heat on battery")
	changes = 0
	context.battery = null
	power_manager.thermal = null
	power.refresh()
	assert_eq(power.get_power_source(), Facade.PowerSource.BATTERY, "still on battery")
	assert_eq(power.get_thermal_status(), Facade.ThermalStatus.SEVERE, "still hot")
	assert_eq(power.recommended_fps_cap(120.0), 30, "the cap holds")
	assert_eq(changes, 0, "a failed read is not a change")


func test_a_failed_refresh_rate_read_keeps_the_last_list() -> void:
	# A thrown Java exception cannot be raised off Android; a Java null where
	# the read needs a value fails the read the same way.
	var sixty_alt := FakeAndroid.Mode.new(60.0)
	sixty_alt.alternatives = PackedFloat32Array([120.0])
	display.current = sixty_alt
	display.modes = [sixty_alt, FakeAndroid.Mode.new(90.0)]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0, 90.0]), "read")
	var broken := FakeAndroid.Mode.new(144.0)
	broken.rate = null
	display.modes = [sixty_alt, broken]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0, 90.0]), "a mode without a rate")
	display.modes = [sixty_alt]
	sixty_alt.width = null
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0, 90.0]), "no current size")
	sixty_alt.width = 1080
	display.modes = null
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0, 90.0]), "no mode list")
	var activity: FakeAndroid.Activity = runtime.activity
	activity.display = null
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0, 90.0]), "no display")
	runtime.activity = null
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0, 90.0]), "paused, no activity")


func test_a_first_failed_refresh_rate_read_is_empty() -> void:
	display.current.height = null
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "never read")
	runtime.activity = null
	assert_eq(_make_backend(34).get_refresh_rates(), PackedFloat32Array(), "no activity yet")


func test_a_good_refresh_rate_read_replaces_the_kept_list() -> void:
	display.modes = [display.current, FakeAndroid.Mode.new(120.0)]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0]), "read")
	display.current.height = null
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0]), "kept")
	display.current.height = 2400
	display.modes = [display.current, FakeAndroid.Mode.new(90.0)]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 90.0]), "a good read replaces it")
	display.modes = [FakeAndroid.Mode.new(120.0, 720, 1600)]
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "an empty reading replaces it")


func test_refresh_rates_below_api_30_are_empty_whatever_was_kept() -> void:
	var gated := _make_backend(29)
	gated._refresh_rates = _rates([60.0, 120.0])
	assert_eq(gated.get_refresh_rates(), PackedFloat32Array())


func test_the_facade_keeps_the_refresh_rates_through_a_failed_poll() -> void:
	display.modes = [display.current, FakeAndroid.Mode.new(120.0)]
	power.set_backend(backend)
	assert_eq(power.get_peak_refresh_rate(), 120.0, "peak")
	changes = 0
	display.current.height = null
	power.refresh()
	runtime.activity = null
	power._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_eq(power.get_refresh_rates(), _rates([60.0, 120.0]), "still the list")
	assert_eq(power.get_peak_refresh_rate(), 120.0, "still the peak")
	assert_eq(changes, 0, "a failed read is not a change")


func test_the_facade_reads_the_fallback() -> void:
	battery.plugged = 0
	power_manager.power_save = 0
	power_manager.thermal = 0
	game_manager.mode = 1
	display.modes = [display.current, FakeAndroid.Mode.new(120.0)]
	power.set_backend(backend)
	assert_eq(power.get_backend_name(), "android")
	assert_eq(power.get_power_source(), Facade.PowerSource.BATTERY, "on battery")
	assert_eq(power.is_power_saver_enabled(), false, "saver off")
	assert_eq(power.get_game_mode(), Facade.GameMode.STANDARD, "standard")
	assert_eq(power.get_thermal_status(), Facade.ThermalStatus.NONE, "cool")
	assert_eq(power.get_refresh_rates(), _rates([60.0, 120.0]), "rates")
	assert_eq(power.get_peak_refresh_rate(), 120.0, "peak")
	assert_eq(power.recommended_fps_cap(120.0), 60, "battery cap")


func test_the_facade_polls_the_fallback_but_reads_game_mode_on_focus() -> void:
	battery.plugged = 0
	game_manager.mode = 1
	power.set_backend(backend)
	changes = 0
	battery.plugged = 1
	game_manager.mode = 3
	power.refresh()
	assert_eq(power.get_power_source(), Facade.PowerSource.EXTERNAL, "polled")
	assert_eq(power.get_game_mode(), Facade.GameMode.STANDARD, "not on a poll")
	assert_eq(changes, 1, "one change")
	power._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(power.get_game_mode(), Facade.GameMode.BATTERY, "read on focus")
	assert_eq(power.recommended_fps_cap(60.0), 30, "battery mode cap")
	assert_eq(changes, 2, "focus change")
