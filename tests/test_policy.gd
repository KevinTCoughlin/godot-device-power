# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## The pure policy: fps_cap(), thermal_back_off(), paced_cap() and
## frame_rate_vote(). No facade state is involved.

const Facade := DevicePowerTestCase.FACADE_SCRIPT
const S := Facade.PowerSource
const M := Facade.GameMode
const T := Facade.ThermalStatus


func test_external_power_is_uncapped_and_battery_is_held() -> void:
	for mode: int in [M.UNSUPPORTED, M.STANDARD, M.CUSTOM]:
		assert_eq(Facade.fps_cap(S.EXTERNAL, false, mode, 120.0), 0, "external, mode %d" % mode)
		assert_eq(Facade.fps_cap(S.BATTERY, false, mode, 120.0), 60, "battery, mode %d" % mode)
		assert_eq(
			Facade.fps_cap(S.UNKNOWN, null, mode, 120.0),
			0,
			"unknown imposes nothing, mode %d" % mode
		)


func test_battery_saver_counts_as_battery() -> void:
	assert_eq(Facade.fps_cap(S.EXTERNAL, true, M.STANDARD, 120.0), 60, "saver on a charger")
	assert_eq(Facade.fps_cap(S.UNKNOWN, true, M.STANDARD, 120.0), 60, "saver, source unknown")


func test_a_saver_that_is_not_a_bool_is_unknown_not_an_error() -> void:
	# Java booleans can arrive as ints; `int == bool` would be a script error,
	# which a release export turns into a silent null.
	assert_eq(Facade.fps_cap(S.EXTERNAL, 0, M.STANDARD, 120.0), 0, "int saver is unknown")
	assert_eq(Facade.fps_cap(S.EXTERNAL, 1, M.STANDARD, 120.0), 0, "a truthy int is still unknown")
	assert_eq(Facade.fps_cap(S.EXTERNAL, "true", M.STANDARD, 120.0), 0, "so is a string")


func test_an_explicit_game_mode_wins_over_the_power_source() -> void:
	assert_eq(Facade.fps_cap(S.BATTERY, false, M.PERFORMANCE, 120.0), 120, "performance on battery")
	assert_eq(Facade.fps_cap(S.EXTERNAL, true, M.PERFORMANCE, 90.0), 90, "performance beats saver")
	assert_eq(Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, 59.94), 60, "refresh rounds")
	assert_eq(Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, 480.0), 240, "at most 240")
	assert_eq(Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, -1.0), 60, "no refresh rate")
	assert_eq(Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, NAN), 60, "NaN refresh rate")
	assert_eq(Facade.fps_cap(S.EXTERNAL, false, M.BATTERY, 120.0), 30, "battery mode on a charger")


func test_the_games_own_numbers_are_used() -> void:
	assert_eq(Facade.fps_cap(S.BATTERY, false, M.STANDARD, 120.0, 45, 20), 45, "custom battery_fps")
	assert_eq(
		Facade.fps_cap(S.BATTERY, false, M.BATTERY, 120.0, 45, 20), 20, "custom battery_mode_fps"
	)


func test_thermal_back_off_levels() -> void:
	assert_eq(Facade.thermal_back_off(T.UNKNOWN), Facade.ThermalBackOff.NONE, "unknown")
	assert_eq(Facade.thermal_back_off(T.NONE), Facade.ThermalBackOff.NONE, "none")
	assert_eq(
		Facade.thermal_back_off(T.LIGHT), Facade.ThermalBackOff.NONE, "light is the platform's"
	)
	assert_eq(Facade.thermal_back_off(T.MODERATE), Facade.ThermalBackOff.MODERATE, "moderate")
	for status: int in [T.SEVERE, T.CRITICAL, T.EMERGENCY, T.SHUTDOWN]:
		assert_eq(
			Facade.thermal_back_off(status), Facade.ThermalBackOff.SEVERE, "status %d" % status
		)


func test_moderate_heat_caps_at_battery_fps() -> void:
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.STANDARD, 120.0, 60, 30, T.MODERATE),
		60,
		"uncapped gets battery_fps"
	)
	assert_eq(
		Facade.fps_cap(S.BATTERY, false, M.STANDARD, 120.0, 60, 30, T.MODERATE), 60, "battery stays"
	)
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.BATTERY, 120.0, 60, 30, T.MODERATE),
		30,
		"a lower cap stays"
	)
	assert_eq(
		Facade.fps_cap(S.UNKNOWN, null, M.UNSUPPORTED, 0.0, 60, 30, T.MODERATE),
		60,
		"even with nothing else known"
	)


func test_severe_heat_caps_at_battery_mode_fps() -> void:
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.STANDARD, 120.0, 60, 30, T.SEVERE), 30, "uncapped"
	)
	assert_eq(Facade.fps_cap(S.BATTERY, false, M.STANDARD, 120.0, 60, 30, T.SEVERE), 30, "battery")
	assert_eq(
		Facade.fps_cap(S.BATTERY, false, M.STANDARD, 120.0, 60, 30, T.SHUTDOWN), 30, "shutdown"
	)


func test_heat_wins_over_performance_mode() -> void:
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, 120.0, 60, 30, T.MODERATE), 60, "moderate"
	)
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, 120.0, 60, 30, T.SEVERE), 30, "severe"
	)
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.PERFORMANCE, 120.0, 60, 30, T.LIGHT),
		120,
		"light does not"
	)


func test_no_heat_changes_nothing() -> void:
	for status: int in [T.UNKNOWN, T.NONE, T.LIGHT]:
		assert_eq(
			Facade.fps_cap(S.EXTERNAL, false, M.STANDARD, 120.0, 60, 30, status),
			0,
			"status %d" % status
		)
		assert_eq(
			Facade.fps_cap(S.BATTERY, false, M.STANDARD, 120.0, 60, 30, status),
			60,
			"status %d" % status
		)


func test_a_zero_limit_imposes_nothing() -> void:
	# A game that sets battery_fps to 0 asked for no battery cap; heat at that
	# level must not turn 0 into a cap of its own.
	assert_eq(
		Facade.fps_cap(S.EXTERNAL, false, M.STANDARD, 120.0, 0, 30, T.MODERATE),
		0,
		"moderate, battery_fps 0"
	)


func test_paced_cap_rounds_up_to_an_even_rate() -> void:
	var pixel := PackedFloat32Array([60.000004, 120.00001])
	var tablet := PackedFloat32Array([90.0])
	assert_eq(Facade.paced_cap(60, pixel), 60, "60 on a 60/120 Hz panel")
	assert_eq(Facade.paced_cap(30, pixel), 30, "30 on a 60/120 Hz panel")
	assert_eq(Facade.paced_cap(60, tablet), 90, "60 on a fixed 90 Hz panel rounds up to 90")
	assert_eq(Facade.paced_cap(30, tablet), 30, "30 on a fixed 90 Hz panel")
	assert_eq(Facade.paced_cap(90, tablet), 90, "the panel's own rate")
	assert_eq(Facade.paced_cap(60, PackedFloat32Array([144.0])), 72, "60 on 144 Hz rounds up to 72")
	assert_eq(Facade.paced_cap(45, tablet), 45, "45 on 90 Hz")
	assert_eq(
		Facade.paced_cap(60, PackedFloat32Array([90.0, 60.0])), 60, "a panel that can switch to 60"
	)
	assert_eq(Facade.paced_cap(60, PackedFloat32Array([59.94])), 60, "59.94 Hz counts as 60")


func test_paced_cap_leaves_what_it_cannot_judge() -> void:
	var tablet := PackedFloat32Array([90.0])
	assert_eq(Facade.paced_cap(100, tablet), 100, "a cap above every rate")
	assert_eq(Facade.paced_cap(0, tablet), 0, "no cap stays no cap")
	assert_eq(Facade.paced_cap(60, PackedFloat32Array()), 60, "unknown rates")
	assert_eq(Facade.paced_cap(60, PackedFloat32Array([NAN, -1.0])), 60, "garbage rates")


func test_frame_rate_vote() -> void:
	assert_eq(Facade.frame_rate_vote(0, 120.0), 120.0, "uncapped votes the peak")
	assert_eq(Facade.frame_rate_vote(60, 120.0), 60.0, "a cap votes the cap")
	assert_eq(Facade.frame_rate_vote(0, 0.0), 0.0, "nothing known, no request")
	assert_eq(Facade.frame_rate_vote(0, -5.0), 0.0, "a negative peak is unknown")
