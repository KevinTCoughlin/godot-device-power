# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## Thermal back-off in the facade: immediate on the way up, held for
## thermal_cooldown seconds of lower status on the way down. Time is the
## fake clock in [member DevicePowerTestCase.now].

const Facade := DevicePowerTestCase.FACADE_SCRIPT
const T := Facade.ThermalStatus
const B := Facade.ThermalBackOff


func before_each() -> void:
	super()
	mock.refresh_rates = PackedFloat32Array([60.0, 120.0])
	mock.power_source = Facade.PowerSource.EXTERNAL
	power.thermal_cooldown = 30.0
	power.set_backend(mock)
	changes = 0


func _heat(status: int, at: float) -> void:
	now = at
	mock.thermal_status = status
	power.refresh()


func test_reads_the_thermal_status() -> void:
	_heat(T.LIGHT, 0.0)
	assert_eq(power.get_thermal_status(), T.LIGHT, "status")
	assert_eq(changes, 1, "a status change emits even without a back-off change")
	assert_eq(power.get_thermal_back_off(), B.NONE, "light does not back off")
	assert_eq(power.recommended_fps_cap(120.0), 0, "uncapped")


func test_backs_off_at_once() -> void:
	_heat(T.MODERATE, 0.0)
	assert_eq(power.get_thermal_back_off(), B.MODERATE, "moderate")
	assert_eq(power.recommended_fps_cap(120.0), 60, "battery_fps")
	_heat(T.SEVERE, 1.0)
	assert_eq(power.get_thermal_back_off(), B.SEVERE, "severe")
	assert_eq(power.recommended_fps_cap(120.0), 30, "battery_mode_fps")


func test_recovers_only_after_the_cooldown() -> void:
	_heat(T.SEVERE, 0.0)
	_heat(T.NONE, 10.0)
	assert_eq(power.get_thermal_back_off(), B.SEVERE, "held right after cooling")
	now = 39.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.SEVERE, "held at 29 s")
	var before := changes
	now = 40.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.NONE, "released at 30 s, without a new reading")
	assert_eq(changes - before, 1, "and the release emits")
	assert_eq(power.recommended_fps_cap(120.0), 0, "uncapped again")


func test_a_flicker_restarts_the_cooldown() -> void:
	_heat(T.MODERATE, 0.0)
	_heat(T.LIGHT, 5.0)
	_heat(T.MODERATE, 20.0)
	_heat(T.LIGHT, 25.0)
	now = 50.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.MODERATE, "only 25 s below since the flicker")
	now = 55.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.NONE, "30 s below")


func test_steps_down_to_the_highest_level_seen_while_cooling() -> void:
	_heat(T.SEVERE, 0.0)
	_heat(T.NONE, 1.0)
	_heat(T.MODERATE, 10.0)
	_heat(T.NONE, 20.0)
	now = 31.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.MODERATE, "moderate was seen during the window")
	now = 60.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.MODERATE, "a new window starts at the step")
	now = 61.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.NONE, "then none")


func test_unknown_status_releases_like_none() -> void:
	_heat(T.SEVERE, 0.0)
	_heat(T.UNKNOWN, 1.0)
	now = 31.0
	power._process(0.0)
	assert_eq(power.get_thermal_back_off(), B.NONE, "unknown imposes nothing, after the cooldown")


func test_heat_wins_over_performance_mode_in_the_facade() -> void:
	mock.game_mode = Facade.GameMode.PERFORMANCE
	power._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(power.recommended_fps_cap(120.0), 120, "performance")
	_heat(T.MODERATE, 0.0)
	assert_eq(power.recommended_fps_cap(120.0), 60, "heat wins")


func test_moderate_heat_is_paced_like_any_cap() -> void:
	# The owner's pacing rule rounds up: on a fixed 90 Hz panel moderate heat
	# (60) gets 90, i.e. no saving; severe heat (30) is paceable and holds.
	mock.refresh_rates = PackedFloat32Array([90.0])
	power._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_heat(T.MODERATE, 0.0)
	assert_eq(power.recommended_fps_cap(90.0), 90, "moderate on fixed 90 Hz")
	_heat(T.SEVERE, 1.0)
	assert_eq(power.recommended_fps_cap(90.0), 30, "severe on fixed 90 Hz")


func test_a_new_backend_starts_cool() -> void:
	_heat(T.SEVERE, 0.0)
	var cool := DevicePowerMockBackend.new()
	power.set_backend(cool)
	assert_eq(power.get_thermal_back_off(), B.NONE, "no back-off carried over")
