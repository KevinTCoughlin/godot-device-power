# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## Linux sysfs power source: the pure decision, then a real directory tree
## (symlinks included, as the kernel lays supplies out) and a zero-length
## read. No device and no charger is required.

const Backend := preload("res://addons/device_power/backends/linux_backend.gd")
const Facade := DevicePowerTestCase.FACADE_SCRIPT
## rw-r--r-- and rwxr-xr-x, to put a fixture back after making it unreadable.
const _READABLE := (
	FileAccess.UNIX_READ_OWNER
	| FileAccess.UNIX_WRITE_OWNER
	| FileAccess.UNIX_READ_GROUP
	| FileAccess.UNIX_READ_OTHER
)
const _LISTABLE := (
	_READABLE
	| FileAccess.UNIX_EXECUTE_OWNER
	| FileAccess.UNIX_EXECUTE_GROUP
	| FileAccess.UNIX_EXECUTE_OTHER
)


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
		[{"MOUSE": _device("Discharging")}, -1, "only a peripheral battery"],
		[{"MOUSE": _device("Full")}, -1, "a full peripheral battery"],
		[{"MOUSE": _device("Charging")}, -1, "a charging peripheral is not mains"],
		[
			{
				"MOUSE": _device("Charging"),
				"AC": _adapter("Mains", "0"),
				"BAT1": _battery("Discharging"),
			},
			0,
			"a charging mouse does not uncap a laptop on battery",
		],
		[
			{"MOUSE": _device("Discharging"), "BAT1": _battery("Discharging")},
			0,
			"the system battery still counts beside a mouse",
		],
		[
			{"MOUSE": _device("Discharging"), "AC": _adapter("Mains", "1")},
			1,
			"mains still counts beside a mouse",
		],
		[{"BAT1": _scoped("Battery", "Discharging", "System")}, 0, "explicit system scope"],
		[{"BAT1": _scoped("Battery", "Discharging", "Unknown")}, 0, "unknown scope still counts"],
		[{"DOCK": _scoped("Mains", "", "Device", "1")}, -1, "a device-scoped adapter is not mains"],
		# No scope at all: the parent bus or the driver's name gives it away.
		[{"MOUSE": _on_bus("hid", "Charging")}, -1, "an unscoped hid battery"],
		[{"PAD": _on_bus("bluetooth", "Discharging")}, -1, "an unscoped bluetooth battery"],
		[{"HEADSET": _on_bus("usb", "Full")}, -1, "an unscoped usb battery"],
		[
			{
				"MOUSE": _on_bus("hid", "Charging"),
				"AC": _adapter("Mains", "0"),
				"BAT0": _on_bus("acpi", "Discharging"),
			},
			0,
			"an unscoped charging hid battery does not uncap a laptop on battery",
		],
		[{"BAT0": _on_bus("acpi", "Discharging")}, 0, "an acpi battery is the machine's"],
		[{"BAT0": _on_bus("platform", "Discharging")}, 0, "a platform battery is the machine's"],
		[{"hidpp_battery_0": _battery("Charging")}, -1, "an unscoped hidpp battery by name"],
		[
			{"hid-00:11:22:33:44:55-battery": _battery("Discharging")},
			-1,
			"an unscoped hid-input battery by name",
		],
		[
			{"wacom_ac_0": _adapter("Mains", "1"), "BAT1": _battery("Discharging")},
			0,
			"a tablet's own adapter is not the machine's mains",
		],
		[
			{"MOUSE": _scoped_on_bus("Battery", "Charging", "Unknown", "hid")},
			-1,
			"an unknown scope on the hid bus is a peripheral",
		],
		[
			{"hidpp_battery_0": _scoped_on_bus("Battery", "Discharging", "System", "hid")},
			0,
			"an explicit system scope beats the bus and the name",
		],
	]
	for row: Array in cases:
		assert_eq(Backend.power_source_from_supplies(row[0]), row[1], row[2])


func test_hid_battery_driver_names_are_peripherals() -> void:
	for supply_name: String in [
		"hid-0005:046D:B023.0004-battery",
		"hidpp_battery_1",
		"sony_controller_battery_00:11:22:33:44:55",
		"ps-controller-battery-00:11:22:33:44:55",
		"nintendo_switch_controller_battery_0005:057E:2009.0006",
		"wacom_battery_0",
		"wiimote_battery_00:11:22:33:44:55",
		"steam-controller-ABC123-battery",
	]:
		assert_true(Backend.is_peripheral(supply_name, _battery("Discharging")), supply_name)
	for supply_name: String in [
		"BAT0", "BAT1", "AC", "ACAD", "ADP1", "ucsi-source-psy-USBC000:001"
	]:
		assert_false(Backend.is_peripheral(supply_name, _battery("Discharging")), supply_name)


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


func test_a_device_scoped_supply_on_disk_is_not_the_computer() -> void:
	# Same layout as sysfs: the files live in real/, and ps/ holds symlinks.
	var base := "/tmp/device-power-sysfs-scope-%d" % Time.get_ticks_usec()
	var real := base.path_join("real")
	var ps := base.path_join("ps")
	_write(real.path_join("hidpp_battery_0").path_join("type"), "Battery\n")
	_write(real.path_join("hidpp_battery_0").path_join("status"), "Charging\n")
	_write(real.path_join("hidpp_battery_0").path_join("scope"), "Device\n")
	_write(real.path_join("BAT1").path_join("type"), "Battery\n")
	_write(real.path_join("BAT1").path_join("status"), "Discharging\n")
	_write(real.path_join("AC").path_join("type"), "Mains\n")
	_write(real.path_join("AC").path_join("online"), "0\n")
	DirAccess.make_dir_recursive_absolute(ps)
	for supply_name: String in ["hidpp_battery_0", "BAT1", "AC"]:
		var target := real.path_join(supply_name)
		var linked: int = OS.execute("/bin/ln", ["-s", target, ps.path_join(supply_name)])
		if linked != 0:
			fail("could not symlink %s" % supply_name)
	var backend: DevicePowerLinuxBackend = Backend.new(ps, func() -> float: return 60.0)
	assert_eq(backend.get_power_source(), 0, "on battery beside a charging mouse")
	var only := base.path_join("only")
	DirAccess.make_dir_recursive_absolute(only)
	var linked_only: int = OS.execute(
		"/bin/ln", ["-s", real.path_join("hidpp_battery_0"), only.path_join("hidpp_battery_0")]
	)
	if linked_only != 0:
		fail("could not symlink the peripheral on its own")
	var desktop: DevicePowerLinuxBackend = Backend.new(only, func() -> float: return 60.0)
	assert_eq(desktop.get_power_source(), -1, "only a peripheral battery is unknown")
	_delete_tree(base)


func test_an_unscoped_peripheral_on_disk_is_found_by_its_bus() -> void:
	# As sysfs: each supply's device link points at its parent, and the
	# parent's subsystem link points at the bus. No scope file anywhere.
	var base := "/tmp/device-power-sysfs-bus-%d" % Time.get_ticks_usec()
	var real := base.path_join("real")
	var ps := base.path_join("ps")
	DirAccess.make_dir_recursive_absolute(real.path_join("bus").path_join("hid"))
	DirAccess.make_dir_recursive_absolute(real.path_join("bus").path_join("acpi"))
	DirAccess.make_dir_recursive_absolute(real.path_join("devices").path_join("mouse0"))
	DirAccess.make_dir_recursive_absolute(real.path_join("devices").path_join("PNP0C0A:00"))
	_write(real.path_join("MOUSE").path_join("type"), "Battery\n")
	_write(real.path_join("MOUSE").path_join("status"), "Charging\n")
	_write(real.path_join("BAT0").path_join("type"), "Battery\n")
	_write(real.path_join("BAT0").path_join("status"), "Discharging\n")
	DirAccess.make_dir_recursive_absolute(ps)
	var links: Array = [
		["../../bus/hid", real.path_join("devices").path_join("mouse0").path_join("subsystem")],
		[
			"../../bus/acpi",
			real.path_join("devices").path_join("PNP0C0A:00").path_join("subsystem")
		],
		[
			real.path_join("devices").path_join("mouse0"),
			real.path_join("MOUSE").path_join("device")
		],
		[
			real.path_join("devices").path_join("PNP0C0A:00"),
			real.path_join("BAT0").path_join("device")
		],
		[real.path_join("MOUSE"), ps.path_join("MOUSE")],
		[real.path_join("BAT0"), ps.path_join("BAT0")],
	]
	for link: Array in links:
		if OS.execute("/bin/ln", ["-s", link[0], link[1]]) != 0:
			fail("could not symlink %s" % link[1])
	assert_eq(Backend._read_subsystem(ps.path_join("MOUSE")), "hid", "the mouse's bus")
	assert_eq(Backend._read_subsystem(ps.path_join("BAT0")), "acpi", "the pack's bus")
	assert_eq(Backend._read_subsystem(real.path_join("devices")), "", "no device link")
	var backend: DevicePowerLinuxBackend = Backend.new(ps, func() -> float: return 60.0)
	assert_eq(backend.get_power_source(), 0, "on battery beside an unscoped charging mouse")
	DirAccess.remove_absolute(ps.path_join("BAT0"))
	assert_eq(backend.get_power_source(), -1, "an unscoped mouse alone is unknown")
	_delete_tree(base)


func test_read_failed() -> void:
	var unreadable := _battery("")
	unreadable["unreadable"] = true
	var gone := _battery("", "0")
	gone["unreadable"] = true
	var mouse := _device("")
	mouse["unreadable"] = true
	var on_hid := _on_bus("hid", "")
	on_hid["unreadable"] = true
	var cases: Array = [
		[{}, false, "nothing enumerated is a reading"],
		[{"BAT1": _battery("Discharging")}, false, "every file read"],
		[{"BAT1": unreadable}, true, "the battery could not be read"],
		[{"AC": _adapter("Mains", "1"), "BAT1": unreadable}, true, "beside an adapter"],
		[{"BAT1": gone}, false, "a pack that is not present does not count"],
		[{"MOUSE": mouse, "BAT1": _battery("Full")}, false, "a scoped peripheral"],
		[{"MOUSE": on_hid, "BAT1": _battery("Full")}, false, "an unscoped peripheral"],
		[{"hidpp_battery_0": unreadable}, false, "a HID battery driver's name"],
		[{"BAT1": {"type": "Battery", "unreadable": "yes"}}, false, "only a real true"],
	]
	for case: Array in cases:
		assert_eq(Backend.read_failed(case[0]), case[1], case[2])


func test_a_failed_read_keeps_the_last_power_source() -> void:
	var base := _make_tree()
	var real := base.path_join("real")
	var root := base.path_join("ps")
	var status := real.path_join("BAT1").path_join("status")
	FileAccess.set_unix_permissions(status, 0)
	if FileAccess.open(status, FileAccess.READ) != null:
		# Root reads any file, so there is no failure to simulate.
		print("  skip: this user can read a mode-000 file")
		_delete_tree(base)
		return
	var first: DevicePowerLinuxBackend = Backend.new(root, func() -> float: return 60.0)
	assert_eq(first.get_power_source(), -1, "a failed first read is unknown")
	FileAccess.set_unix_permissions(status, _READABLE)
	var backend: DevicePowerLinuxBackend = Backend.new(root, func() -> float: return 60.0)
	assert_eq(backend.get_power_source(), 0, "on battery")
	FileAccess.set_unix_permissions(status, 0)
	assert_eq(backend.get_power_source(), 0, "an unreadable status keeps battery")
	FileAccess.set_unix_permissions(root, 0)
	assert_eq(backend.get_power_source(), 0, "an unlistable power_supply keeps battery")
	FileAccess.set_unix_permissions(root, _LISTABLE)
	FileAccess.set_unix_permissions(status, _READABLE)
	_write(real.path_join("ACAD").path_join("online"), "1\n")
	assert_eq(backend.get_power_source(), 1, "a good read replaces it")
	DirAccess.remove_absolute(root.path_join("ACAD"))
	DirAccess.remove_absolute(root.path_join("BAT1"))
	assert_eq(backend.get_power_source(), -1, "supplies that are gone are a real change")
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


## A peripheral supply: scope Device, as hidpp and other device batteries report.
func _device(status: String) -> Dictionary:
	return _scoped("Battery", status, "Device")


func _scoped(type: String, status: String, scope: String, online: String = "") -> Dictionary:
	var supply := _pack(type, status, online)
	supply["scope"] = scope
	return supply


## A supply with no scope file whose parent device sits on [param bus].
func _on_bus(bus: String, status: String) -> Dictionary:
	var supply := _battery(status)
	supply["subsystem"] = bus
	return supply


func _scoped_on_bus(type: String, status: String, scope: String, bus: String) -> Dictionary:
	var supply := _scoped(type, status, scope)
	supply["subsystem"] = bus
	return supply


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
