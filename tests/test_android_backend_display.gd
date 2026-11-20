# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends "res://tests/android_backend_case.gd"

## DevicePowerAndroidBackend's display reads: which refresh rates count
## (current resolution, alternatives from API 31, noise and garbage), and
## the frame rate vote without a render surface.


func test_refresh_rates_need_api_30() -> void:
	display.modes = [display.current, FakeAndroid.Mode.new(120.0)]
	assert_eq(_make_backend(29).get_refresh_rates(), PackedFloat32Array(), "API 29")
	assert_eq(_make_backend(30).get_refresh_rates(), _rates([60.0, 120.0]), "API 30")


func test_only_modes_at_the_current_resolution_count() -> void:
	display.modes = [
		display.current,
		FakeAndroid.Mode.new(120.0),
		FakeAndroid.Mode.new(90.0, 720, 1600),
		FakeAndroid.Mode.new(144.0, 1080, 1600),
	]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0]))


func test_float_dimensions_match_int_ones() -> void:
	display.modes = [display.current, FakeAndroid.Mode.new(120.0, 1080.0, 2400.0)]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 120.0]))


func test_float_noise_is_merged() -> void:
	display.modes = [
		FakeAndroid.Mode.new(60.0000038),
		FakeAndroid.Mode.new(60.0),
		FakeAndroid.Mode.new(120.0000076),
	]
	var rates := backend.get_refresh_rates()
	assert_eq(rates.size(), 2, "60 and 120: %s" % [rates])


func test_alternative_rates_need_api_31() -> void:
	# A Pixel 10: the 60 Hz mode lists 120 as an alternative, and the other
	# way round; a 1 Hz alternative is only on the 120 Hz mode.
	var sixty := FakeAndroid.Mode.new(60.0)
	sixty.alternatives = PackedFloat32Array([120.0])
	var one_twenty := FakeAndroid.Mode.new(120.0)
	one_twenty.alternatives = PackedFloat32Array([60.0, 1.0])
	display.current = sixty
	display.modes = [sixty, one_twenty]
	assert_eq(_make_backend(30).get_refresh_rates(), _rates([60.0, 120.0]), "API 30")
	assert_eq(_make_backend(31).get_refresh_rates(), _rates([60.0, 120.0, 1.0]), "API 31")


func test_alternatives_of_other_resolutions_are_ignored() -> void:
	var other := FakeAndroid.Mode.new(60.0, 720, 1600)
	other.alternatives = [30.0]
	display.modes = [display.current, other]
	assert_eq(backend.get_refresh_rates(), _rates([60.0]))


func test_null_alternatives_are_none() -> void:
	display.current.alternatives = null
	assert_eq(backend.get_refresh_rates(), _rates([60.0]))


func test_unusable_rates_are_dropped() -> void:
	display.current.alternatives = [0.0, -60.0, INF, NAN, "90", null, 90]
	display.modes = [null, display.current, FakeAndroid.Mode.new("120")]
	assert_eq(backend.get_refresh_rates(), _rates([60.0, 90.0]))


func test_a_mode_without_a_size_makes_the_read_unknown() -> void:
	var broken := FakeAndroid.Mode.new(120.0)
	broken.width = null
	display.modes = [display.current, broken]
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "one bad mode, no guess")


func test_a_missing_display_or_mode_list_is_unknown() -> void:
	display.modes = null
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "no mode list")
	display.modes = [display.current]
	display.current = null
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "no current mode")
	runtime.activity.display = null
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "no display")
	runtime.activity = null
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array(), "no activity")


func test_the_current_mode_without_a_size_is_unknown() -> void:
	display.current.height = null
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array())


func test_no_vote_without_a_render_surface() -> void:
	assert_false(_make_backend(30).vote_frame_rate(60.0), "API 30")
	assert_false(backend.vote_frame_rate(60.0), "the Godot class cannot be wrapped here")
