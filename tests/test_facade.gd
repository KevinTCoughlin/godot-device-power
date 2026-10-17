# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## The facade over a polled backend: reads, signals, the recommendation and
## the frame rate vote.

const Facade := DevicePowerTestCase.FACADE_SCRIPT
const S := Facade.PowerSource
const M := Facade.GameMode


func before_each() -> void:
	super()
	mock.refresh_rates = PackedFloat32Array([60.0, 120.0])
	power.set_backend(mock)
	changes = 0
	mock.votes.clear()
	power._voted = -1.0
	power._vote()


func test_set_backend_reads_and_emits_once() -> void:
	var fresh := make_facade()
	var before := changes
	fresh.set_backend(mock)
	assert_eq(changes - before, 1, "set_backend emits once")
	assert_eq(fresh.get_backend_name(), "mock")
	assert_eq(fresh.get_peak_refresh_rate(), 120.0, "the peak")
	fresh.free()


func test_unknown_state_imposes_no_cap() -> void:
	assert_eq(typeof(power.recommended_fps_cap(120.0)), TYPE_INT, "the cap is an int")
	assert_eq(power.recommended_fps_cap(120.0), 0, "unknown state, no cap")
	assert_eq(mock.votes, [120.0] as Array[float], "an uncapped game votes the peak")


func test_an_unchanged_poll_is_silent() -> void:
	power.refresh()
	assert_eq(changes, 0, "no signal")
	assert_eq(mock.votes.size(), 1, "the vote is not resent")


func test_unplugging_and_plugging_in() -> void:
	mock.power_source = S.BATTERY
	power.refresh()
	assert_eq(changes, 1, "unplugging emits")
	assert_eq(power.get_power_source(), S.BATTERY, "reads the source")
	assert_eq(power.recommended_fps_cap(120.0), 60, "battery cap")
	mock.power_source = S.EXTERNAL
	power.refresh()
	assert_eq(changes, 2, "plugging in emits")
	assert_eq(power.recommended_fps_cap(120.0), 0, "external, uncapped")


func test_the_vote_follows_the_games_cap() -> void:
	Engine.max_fps = 60
	power._process(0.0)
	assert_eq(mock.votes.back(), 60.0, "votes the game's cap within a frame")
	Engine.max_fps = 30
	power._process(0.0)
	assert_eq(mock.votes.back(), 30.0, "a menu cap is voted too")
	Engine.max_fps = 0
	power._process(0.0)
	assert_eq(mock.votes.back(), 120.0, "uncapped votes the peak again")


func test_resuming_resends_the_vote_and_asks_for_an_update() -> void:
	var before := mock.votes.size()
	power._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_eq(mock.votes.size(), before + 1, "resuming resends the vote")
	assert_eq(mock.update_requests, 1, "and asks the backend to re-read")


func test_a_failed_vote_is_retried_on_polls_not_every_frame() -> void:
	mock.vote_ok = false
	Engine.max_fps = 60
	power._process(0.0)
	var before := mock.votes.size()
	power._process(0.0)
	power._process(0.0)
	assert_eq(mock.votes.size(), before, "not every frame")
	mock.vote_ok = true
	power.refresh()
	assert_eq(mock.votes.size(), before + 1, "a poll retries it")
	power.refresh()
	assert_eq(mock.votes.size(), before + 1, "and stops once it is made")


func test_polls_happen_on_the_interval() -> void:
	mock.power_source = S.BATTERY
	power._process(power.poll_interval * 0.5)
	assert_eq(changes, 0, "not yet")
	power._process(power.poll_interval * 0.6)
	assert_eq(changes, 1, "polled")


func test_vote_frame_rate_off_sends_nothing() -> void:
	power.vote_frame_rate = false
	Engine.max_fps = 45
	power._process(0.0)
	power.refresh()
	assert_eq(mock.votes.size(), 1, "only the vote made before it was turned off")


func test_a_polled_backends_game_mode_is_read_on_focus_only() -> void:
	mock.game_mode = M.BATTERY
	power.refresh()
	assert_eq(power.get_game_mode(), M.UNSUPPORTED, "a poll does not read the game mode")
	power._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(power.get_game_mode(), M.BATTERY, "focus reads it")
	assert_eq(power.recommended_fps_cap(120.0), 30, "battery mode")
	mock.game_mode = M.PERFORMANCE
	power._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_eq(power.recommended_fps_cap(0.0), 120, "performance uses the peak")


func test_a_saver_that_is_not_a_bool_reads_as_unknown() -> void:
	mock.power_saver = 1
	power.refresh()
	assert_null(power.is_power_saver_enabled(), "an int saver is unknown")
	assert_eq(changes, 0, "and changes nothing")
	mock.power_saver = true
	power.refresh()
	assert_eq(power.is_power_saver_enabled(), true, "reads the saver")
	assert_eq(changes, 1, "a saver change emits")


func test_out_of_range_backend_values_are_unknown() -> void:
	mock.power_source = 7
	mock.game_mode = 99
	mock.thermal_status = 42
	power._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(power.get_power_source(), S.UNKNOWN, "source")
	assert_eq(power.get_game_mode(), M.UNSUPPORTED, "game mode")
	assert_eq(power.get_thermal_status(), Facade.ThermalStatus.UNKNOWN, "thermal")


func test_garbage_refresh_rates_are_unknown() -> void:
	var bad := DevicePowerMockBackend.new()
	bad.refresh_rates = PackedFloat32Array([NAN, -5.0])
	var broken := make_facade()
	broken.set_backend(bad)
	assert_eq(broken.get_peak_refresh_rate(), 0.0, "no peak")
	assert_eq(broken.get_refresh_rates().size(), 0, "dropped")
	assert_eq(bad.votes, [0.0] as Array[float], "nothing known: the vote is withdrawn")
	broken.free()


func test_the_null_backend_imposes_nothing() -> void:
	var plain := make_facade()
	plain.set_backend(DevicePowerNullBackend.new())
	assert_eq(plain.get_power_source(), S.UNKNOWN, "source")
	assert_eq(plain.get_game_mode(), M.UNSUPPORTED, "game mode")
	assert_eq(plain.get_thermal_status(), Facade.ThermalStatus.UNKNOWN, "thermal")
	assert_eq(plain.recommended_fps_cap(120.0), 0, "no cap")
	assert_eq(plain.get_peak_refresh_rate(), 0.0, "no peak")
	plain.free()


func test_the_recommendation_is_paced_to_a_fixed_90_hz_panel() -> void:
	# Battery keeps 90 (60 cannot be paced there); Battery game mode gets 30.
	var tab_mock := DevicePowerMockBackend.new()
	tab_mock.refresh_rates = PackedFloat32Array([90.0])
	tab_mock.power_source = S.BATTERY
	var tab := make_facade()
	tab.set_backend(tab_mock)
	assert_eq(tab.recommended_fps_cap(90.0), 90, "battery")
	tab_mock.game_mode = M.BATTERY
	tab._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(tab.recommended_fps_cap(90.0), 30, "battery game mode")
	tab_mock.game_mode = M.STANDARD
	tab._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	tab_mock.power_source = S.EXTERNAL
	tab.refresh()
	assert_eq(tab.recommended_fps_cap(90.0), 0, "external, uncapped")
	tab.free()


func test_a_pushing_backend_is_read_on_its_signal() -> void:
	var pusher := DevicePowerMockBackend.new()
	pusher.push = true
	var facade := make_facade()
	facade.set_backend(pusher)
	var before := changes
	pusher.power_source = S.BATTERY
	pusher.game_mode = M.BATTERY
	pusher.push_change()
	assert_eq(changes - before, 1, "one signal for the push")
	assert_eq(facade.get_power_source(), S.BATTERY, "source read on the push")
	assert_eq(facade.get_game_mode(), M.BATTERY, "a pushing backend's game mode is read every time")
	facade.free()


func test_a_pushing_backend_is_polled_only_as_a_safety_net() -> void:
	var pusher := DevicePowerMockBackend.new()
	pusher.push = true
	var facade := make_facade()
	facade.set_backend(pusher)
	var before := changes
	pusher.power_source = S.BATTERY
	facade._process(facade.poll_interval * 2.0)
	assert_eq(changes - before, 0, "the normal poll interval does not apply")
	facade._process(facade.safety_poll_interval)
	assert_eq(changes - before, 1, "the safety poll does")
	facade.safety_poll_interval = 0.0
	pusher.power_source = S.EXTERNAL
	facade._process(1000.0)
	assert_eq(changes - before, 1, "0 turns the safety poll off")
	facade.free()


func test_replacing_the_backend_disconnects_the_old_one() -> void:
	var first := DevicePowerMockBackend.new()
	first.push = true
	var facade := make_facade()
	facade.set_backend(first)
	facade.set_backend(DevicePowerNullBackend.new())
	var before := changes
	first.push_change()
	assert_eq(changes - before, 0, "the old backend is no longer heard")
	facade.free()
