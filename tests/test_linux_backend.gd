# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## Linux sysfs power source: the pure decision, then a real directory tree
## (symlinks included, as the kernel lays supplies out) and a zero-length
## read. No device and no charger is required.

const Backend := preload("res://addons/device_power/backends/linux_backend.gd")
const Facade := DevicePowerTestCase.FACADE_SCRIPT


func test_power_source_from_supplies() -> void:
	var cases: Array = [
		[{}, -1, "nothing enumerated"],
		[{"BAT1": _battery("Discharging")}, 0, "battery only, discharging"],
		[{"BAT1": _battery("Not charging")}, 0, "unplugged, not charging"],
		[{"BAT1": _battery("Full")}, 0, "unplugged at full"],
		[{"BAT1": _battery("Unknown")}, -1, "status unknown and no adapter"],
		[{"BAT1": _battery("Charging")}, 1, "charging without an adapter device"],
		[
			{"AC": _adapter("Mains", "1"), "BAT1": _battery("Discharging")},
			1,
			"plugged wins over discharging",
		],
		[
			{"AC": _adapter("Mains", "1"), "BAT1": _battery("Not charging")},
			1,
			"charge limit stays external",
		],
		[{"AC": _adapter("Mains", "1"), "BAT1": _battery("Full")}, 1, "plugged and full"],
		[
			{"AC": _adapter("Mains", "0"), "BAT1": _battery("Discharging")},
			0,
			"adapter present but offline",
		],
		[{"AC": _adapter("Mains", "0"), "BAT1": _battery("Full")}, 0, "full and unplugged"],
		[
			{"AC": _adapter("Mains", "0"), "BAT1": _battery("Unknown")},
			0,
			"offline adapter, status unreadable",
		],
		[{"AC": _adapter("Mains", "0")}, -1, "offline adapter and no battery"],
		[{"AC": _adapter("Mains", "1")}, 1, "mains and no battery"],
		[{"W": _adapter("Wireless", "1"), "BAT1": _battery("Not charging")}, 1, "wireless"],
		[{"BAT1": _battery("Discharging", "0")}, -1, "battery not present"],
		[{"UPS1": _pack("UPS", "Discharging")}, 0, "a discharging ups is battery"],
		[
			{"AC": _adapter("Mains", "1\n"), "BAT1": _battery("Not charging\n")},
			1,
			"trailing newlines",
		],
		[{"X": _adapter("Unknown", "1")}, -1, "an unknown type is not an adapter"],
		[{"nope": "not a supply", "BAT1": _battery("Discharging")}, 0, "garbage entry ignored"],
	]
	for row: Array in cases:
		assert_eq(Backend.power_source_from_supplies(row[0]), row[1], row[2])


func test_every_adapter_type_online_is_external() -> void:
	for type: String in [
		"Mains",
		"USB",
		"USB_DCP",
		"USB_CDP",
		"USB_ACA",
		"USB_C",
		"USB_PD",
		"USB_PD_DRP",
		"BrickID",
		"Wireless",
	]:
		var supplies := {"AD": _adapter(type, "1"), "BAT1": _battery("Discharging")}
		assert_eq(Backend.power_source_from_supplies(supplies), 1, type)


func test_a_missing_root_is_unknown_without_an_error() -> void:
	var backend: DevicePowerLinuxBackend = Backend.new("/tmp/device-power-no-such-root")
	assert_eq(backend.get_power_source(), -1, "missing sysfs root")
	assert_eq(backend.get_backend_name(), "linux")
	assert_false(backend.pushes_changes(), "polled")
	assert_false(backend.can_vote_frame_rate(), "no compositor vote")
	assert_false(backend.vote_frame_rate(60.0), "vote is not made")
	assert_null(backend.is_power_saver_enabled(), "saver")
	assert_eq(backend.get_game_mode(), 0, "game mode")
	assert_eq(backend.get_thermal_status(), -1, "thermal")


func test_the_current_refresh_rate_is_the_only_rate() -> void:
	var backend: DevicePowerLinuxBackend = Backend.new(
		"/tmp/device-power-no-such-root", func() -> float: return 144.0
	)
	assert_eq(backend.get_refresh_rates(), PackedFloat32Array([144.0]), "one rate")
	var none: DevicePowerLinuxBackend = Backend.new(
		"/tmp/device-power-no-such-root", func() -> float: return -1.0
	)
	assert_eq(none.get_refresh_rates(), PackedFloat32Array(), "headless / unknown")
	var garbage: DevicePowerLinuxBackend = Backend.new(
		"/tmp/device-power-no-such-root", func() -> Variant: return "144"
	)
	assert_eq(garbage.get_refresh_rates(), PackedFloat32Array(), "a string is not a rate")


func test_a_fixture_tree_is_reread_including_through_symlinks() -> void:
	var base := _make_tree()
	var root := base.path_join("ps")
	var backend: DevicePowerLinuxBackend = Backend.new(root, func() -> float: return 90.0)
	assert_eq(backend.get_power_source(), 0, "unplugged")
	_write(base.path_join("real").path_join("ACAD").path_join("online"), "1\n")
	assert_eq(backend.get_power_source(), 1, "plugged in on the next read, not cached")
	var facade := make_facade()
	facade.set_backend(backend)
	assert_eq(facade.get_power_source(), Facade.PowerSource.EXTERNAL, "facade")
	assert_eq(facade.get_thermal_status(), Facade.ThermalStatus.UNKNOWN, "no heat guess")
	assert_null(facade.is_power_saver_enabled(), "no saver guess")
	assert_eq(facade.recommended_fps_cap(90.0), 0, "external stays uncapped")
	_write(base.path_join("real").path_join("ACAD").path_join("online"), "0\n")
	facade.refresh()
	assert_eq(facade.get_power_source(), Facade.PowerSource.BATTERY, "unplugged on a poll")
	# 60 cannot be shown evenly on a panel fixed at the current 90 Hz, so the
	# battery cap paces up. The other modes a monitor might offer are unknown.
	assert_eq(facade.recommended_fps_cap(90.0), 90, "paced to the current rate")
	facade.free()
	_delete_tree(base)


func test_a_zero_length_special_file_is_still_read() -> void:
	# proc files report length 0. get_file_as_string() returns "" for them.
	var path := "/proc/self/comm"
	if FileAccess.file_exists(path):
		var text := Backend._read_value(path)
		assert_false(text.is_empty(), "proc comm was empty")
		assert_false(text.contains("\n"), "stripped: %s" % text)
	var base := _make_tree()
	var status := base.path_join("real").path_join("BAT1").path_join("status")
	assert_eq(Backend._read_value(status), "Discharging", "a normal file, newline stripped")
	_delete_tree(base)


func _battery(status: String, present: String = "") -> Dictionary:
	return _pack("Battery", status, "", present)


func _pack(type: String, status: String, online: String = "", present: String = "") -> Dictionary:
	return {"type": type, "status": status, "online": online, "present": present}


func _adapter(type: String, online: String) -> Dictionary:
	return _pack(type, "", online, "")


## A throwaway sysfs lookalike: root/real holds the files, root/ps is what the
## backend opens, and its entries are symlinks, as on a real machine.
func _make_tree() -> String:
	var base := "/tmp/device-power-sysfs-%d" % Time.get_ticks_usec()
	var real := base.path_join("real")
	var ps := base.path_join("ps")
	_write(real.path_join("BAT1").path_join("type"), "Battery\n")
	_write(real.path_join("BAT1").path_join("status"), "Discharging\n")
	_write(real.path_join("BAT1").path_join("present"), "1\n")
	_write(real.path_join("ACAD").path_join("type"), "Mains\n")
	_write(real.path_join("ACAD").path_join("online"), "0\n")
	DirAccess.make_dir_recursive_absolute(ps)
	var link_battery := OS.execute("/bin/ln", ["-s", real.path_join("BAT1"), ps.path_join("BAT1")])
	var link_mains := OS.execute("/bin/ln", ["-s", real.path_join("ACAD"), ps.path_join("ACAD")])
	if link_battery != 0 or link_mains != 0:
		fail("could not symlink the fixture supplies")
	return base


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("could not write %s" % path)
		return
	file.store_string(text)
	file.close()


func _delete_tree(path: String) -> void:
	# Only trees this fixture created. rm handles the symlinks without
	# following them into somewhere else; the targets live under the same root.
	if not path.begins_with("/tmp/device-power-sysfs-"):
		fail("refusing to delete %s" % path)
		return
	OS.execute("/bin/rm", ["-rf", path])
