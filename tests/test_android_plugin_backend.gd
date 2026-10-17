# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## DevicePowerAndroidPluginBackend over a fake DevicePowerAndroid singleton:
## value checking, signals, and the facade on top of it.

const Facade := DevicePowerTestCase.FACADE_SCRIPT
const FakePlugin := preload("res://tests/fake_plugin.gd")

var plugin: Object = null
var backend: DevicePowerAndroidPluginBackend = null


func before_each() -> void:
	super()
	plugin = FakePlugin.new()
	backend = DevicePowerAndroidPluginBackend.new(plugin)


func after_each() -> void:
	super()
	backend = null
	if plugin != null:
		plugin.free()
		plugin = null


func test_reads_well_formed_values() -> void:
	plugin.power_source = 1
	plugin.power_saver = 0
	plugin.game_mode = 2
	plugin.thermal_status = 3
	plugin.refresh_rates = PackedFloat32Array([60.0, 120.0])
	assert_true(backend.is_compatible(), "API version 1")
	assert_true(backend.pushes_changes(), "pushes")
	assert_eq(backend.get_backend_name(), "android_plugin")
	assert_eq(backend.get_power_source(), 1, "external")
	assert_eq(backend.is_power_saver_enabled(), false, "saver off")
	assert_eq(backend.get_game_mode(), 2, "performance")
	assert_eq(backend.get_thermal_status(), 3, "severe")
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array([60.0, 120.0]), "rates")
	plugin.power_saver = 1
	assert_eq(backend.is_power_saver_enabled(), true, "saver on")


func test_wrong_types_read_as_unknown() -> void:
	# Each of these would be a script error somewhere in a careless caller.
	plugin.power_source = true
	plugin.power_saver = true
	plugin.game_mode = "2"
	plugin.thermal_status = 3.0
	plugin.refresh_rates = "60,120"
	assert_eq(backend.get_power_source(), -1, "a bool source")
	assert_null(backend.is_power_saver_enabled(), "a bool saver is not the plugin's tri-state")
	assert_eq(backend.get_game_mode(), 0, "a string game mode")
	assert_eq(backend.get_thermal_status(), -1, "a float status")
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "a string of rates")
	plugin.power_source = null
	plugin.refresh_rates = null
	assert_eq(backend.get_power_source(), -1, "null source")
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "null rates")


func test_out_of_range_values_read_as_unknown() -> void:
	plugin.power_source = 5
	plugin.power_saver = 2
	plugin.game_mode = 9
	plugin.thermal_status = 7
	assert_eq(backend.get_power_source(), -1, "source")
	assert_null(backend.is_power_saver_enabled(), "saver")
	assert_eq(backend.get_game_mode(), 0, "game mode")
	assert_eq(backend.get_thermal_status(), -1, "thermal")


func test_refresh_rates_drop_garbage_and_accept_other_array_types() -> void:
	plugin.refresh_rates = PackedFloat64Array([90.0, NAN, -1.0, 0.0])
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array([90.0]), "float64 array")
	plugin.refresh_rates = [60, "x", null, 120.0]
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array([60.0, 120.0]), "a plain array")


func test_duplicate_rates_are_merged_within_half_a_hertz() -> void:
	# A Pixel 10 through the JavaClassWrapper backend: the 60 Hz mode's
	# alternative 120 repeated the 120 Hz mode, with float noise.
	plugin.refresh_rates = PackedFloat32Array([60.0000038, 120.0000076, 120.0000076, 119.7])
	assert_eq(
		backend.get_refresh_rates(), PackedFloat32Array([60.0000038, 120.0000076]), "one of each"
	)


func test_merge_refresh_rate() -> void:
	var rates := PackedFloat32Array()
	assert_true(DevicePowerBackend.merge_refresh_rate(rates, 60.0000038), "first 60")
	assert_true(DevicePowerBackend.merge_refresh_rate(rates, 120.0000076), "first 120")
	assert_false(DevicePowerBackend.merge_refresh_rate(rates, 120.0000076), "exact repeat")
	assert_false(DevicePowerBackend.merge_refresh_rate(rates, 120.4), "within 0.5 Hz")
	assert_false(DevicePowerBackend.merge_refresh_rate(rates, 59.94), "59.94 is 60")
	assert_true(DevicePowerBackend.merge_refresh_rate(rates, 90.0), "a new rate")
	assert_false(DevicePowerBackend.merge_refresh_rate(rates, NAN), "NaN")
	assert_false(DevicePowerBackend.merge_refresh_rate(rates, 0.0), "zero")
	assert_false(DevicePowerBackend.merge_refresh_rate(rates, -60.0), "negative")
	assert_eq(
		rates, PackedFloat32Array([60.0000038, 120.0000076, 90.0]), "first seen kept, in order"
	)


func test_vote_results() -> void:
	assert_true(backend.vote_frame_rate(120.0), "true")
	assert_eq(plugin.votes, [120.0], "passed through")
	plugin.vote_result = false
	assert_false(backend.vote_frame_rate(60.0), "false")
	plugin.vote_result = 1
	assert_true(backend.vote_frame_rate(60.0), "an int 1 counts")
	plugin.vote_result = null
	assert_false(backend.vote_frame_rate(60.0), "null is not made")
	plugin.vote_result = "yes"
	assert_false(backend.vote_frame_rate(60.0), "nor is a string")


func test_garbage_rates_are_not_sent() -> void:
	assert_false(backend.vote_frame_rate(NAN), "NaN")
	assert_false(backend.vote_frame_rate(-1.0), "negative")
	assert_false(backend.vote_frame_rate(INF), "infinite")
	assert_eq(plugin.votes, [], "none reached the plugin")


func test_request_update_asks_the_plugin_to_refresh() -> void:
	backend.request_update()
	assert_eq(plugin.refreshes, 1)


func test_every_plugin_signal_becomes_changed() -> void:
	var seen := [0]
	backend.changed.connect(func() -> void: seen[0] += 1)
	plugin.emit_signal("power_changed", 0, 1)
	plugin.emit_signal("game_mode_changed", 3)
	plugin.emit_signal("thermal_status_changed", 2)
	plugin.emit_signal("refresh_rates_changed")
	assert_eq(seen[0], 4, "one changed per plugin signal")


func test_an_incompatible_plugin_is_left_alone() -> void:
	var old := FakePlugin.new()
	old.api_version = 2
	var other := DevicePowerAndroidPluginBackend.new(old)
	assert_false(other.is_compatible(), "API 2")
	assert_false(old.is_connected("power_changed", other._on_plugin_signal), "no signals connected")
	old.api_version = true
	assert_false(other.is_compatible(), "a bool version is not 1")
	old.free()


func test_a_missing_method_reads_as_unknown() -> void:
	# A plugin without a method (an older AAR, say) raises a script error in
	# the call; the backend must turn the resulting null into "unknown".
	# Three calls fail: getApiVersion in _init and below, getThermalStatus.
	expect_errors(3)
	var bare := Object.new()
	var other := DevicePowerAndroidPluginBackend.new(bare)
	assert_false(other.is_compatible(), "no getApiVersion")
	assert_eq(other.get_thermal_status(), -1, "no getThermalStatus")
	bare.free()


func test_the_facade_follows_the_plugins_signals() -> void:
	plugin.refresh_rates = PackedFloat32Array([60.0, 120.0])
	plugin.power_source = 1
	power.set_backend(backend)
	assert_eq(power.get_backend_name(), "android_plugin")
	assert_eq(power.recommended_fps_cap(120.0), 0, "external")
	var before := changes
	plugin.power_source = 0
	plugin.emit_signal("power_changed", 0, 0)
	assert_eq(changes - before, 1, "the signal is read at once")
	assert_eq(power.get_power_source(), Facade.PowerSource.BATTERY, "battery")
	assert_eq(power.recommended_fps_cap(120.0), 60, "battery cap")
	plugin.thermal_status = 3
	plugin.emit_signal("thermal_status_changed", 3)
	assert_eq(power.recommended_fps_cap(120.0), 30, "severe heat")
	plugin.game_mode = 3
	plugin.emit_signal("game_mode_changed", 3)
	assert_eq(power.get_game_mode(), Facade.GameMode.BATTERY, "game mode read on its signal")


func test_the_facade_votes_through_the_plugin() -> void:
	plugin.refresh_rates = PackedFloat32Array([60.0, 120.0])
	power.set_backend(backend)
	assert_eq(plugin.votes.back(), 120.0, "the peak, uncapped")
	Engine.max_fps = 30
	power._process(0.0)
	assert_eq(plugin.votes.back(), 30.0, "the game's cap")


func test_the_facade_asks_the_plugin_to_refresh_on_focus() -> void:
	power.set_backend(backend)
	power._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(plugin.refreshes, 1)
