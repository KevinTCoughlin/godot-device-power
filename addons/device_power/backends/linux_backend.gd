# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerLinuxBackend
extends DevicePowerBackend

## Power source on Linux, including Steam Deck, from the kernel's
## [code]/sys/class/power_supply[/code].
##
## Godot 4 has no power API. [code]OS.get_power_state()[/code] was removed
## before 4.0, and it was never implemented for every desktop in the first
## place. sysfs is world-readable and needs no permission, no daemon and no
## process. Supplies are usually symlinks; directory listing follows that.
##
## [b]Plugged in wins.[/b] An adapter whose [code]online[/code] file is
## [code]1[/code] (mains, USB-C, wireless) is external power, even when the
## battery says [code]Discharging[/code] or [code]Not charging[/code]. A
## charge limit looks like "not charging" while the adapter stays online, and
## that is still a charger, the same rule as Android's [code]plugged[/code]
## extra. [code]Charging[/code] is external power even if no adapter device
## is enumerated. Anything else with a battery that is present is battery.
## No supply, a supply that cannot be read, or a status of [code]Unknown[/code]
## with no adapter is unknown, and the policy imposes nothing.
##
## Battery saver, game mode and thermal status are not here. Mapping a raw
## zone temperature onto Android's thermal enum would be a guess, so heat
## imposes nothing. The frame-rate vote is not made: nothing portable asks a
## desktop compositor to change rate. The current refresh rate is reported,
## so a cap is paced as if the panel were fixed at that rate. Other modes the
## monitor could switch to are invisible.

## Kernel [code]power_supply[/code] class directory.
const POWER_SUPPLY_ROOT := "/sys/class/power_supply"
## [code]DevicePower.PowerSource[/code], copied so this file does not depend
## on the facade.
const _SOURCE_UNKNOWN := -1
const _SOURCE_BATTERY := 0
const _SOURCE_EXTERNAL := 1
## [code]POWER_SUPPLY_TYPE_TEXT[/code] values that mean "something is feeding
## the machine" when [code]online[/code] is [code]1[/code]. A battery's own
## [code]online[/code] file, on drivers that have one, means the pack is
## connected, not that a charger is.
const _ADAPTER_TYPES := {
	"Mains": true,
	"USB": true,
	"USB_DCP": true,
	"USB_CDP": true,
	"USB_ACA": true,
	"USB_C": true,
	"USB_PD": true,
	"USB_PD_DRP": true,
	"BrickID": true,
	"Wireless": true,
}
const _BATTERY_TYPES := {"Battery": true, "UPS": true}
## sysfs and proc files report a length of 0, so a read must stop on its own.
const _VALUE_MAX_BYTES := 128

var _root: String
var _read_refresh_rate: Callable


func _init(root: String = POWER_SUPPLY_ROOT, read_refresh_rate: Callable = Callable()) -> void:
	_root = root
	_read_refresh_rate = (
		read_refresh_rate if read_refresh_rate.is_valid() else _screen_refresh_rate
	)


func get_backend_name() -> String:
	return "linux"


func get_power_source() -> int:
	return power_source_from_supplies(_read_supplies(_root))


func get_refresh_rates() -> PackedFloat32Array:
	var rates := PackedFloat32Array()
	var rate: Variant = _read_refresh_rate.call()
	if rate is float or rate is int:
		merge_refresh_rate(rates, float(rate))
	return rates


## The [enum DevicePower.PowerSource] value for supplies already read.
## Each value is a Dictionary with string fields [code]type[/code],
## [code]status[/code], [code]online[/code] and [code]present[/code], as the
## sysfs files read after stripping. A missing file is an empty string. A
## [code]present[/code] of [code]0[/code] drops that supply.
static func power_source_from_supplies(supplies: Dictionary) -> int:
	var adapter_online := false
	var adapter_present := false
	var battery_present := false
	var battery_charging := false
	var battery_known := false
	for raw in supplies.values():
		if not raw is Dictionary:
			continue
		var supply: Dictionary = raw
		if _field(supply, "present") == "0":
			continue
		var type := _field(supply, "type")
		var status := _field(supply, "status")
		var online := _field(supply, "online")
		if _ADAPTER_TYPES.has(type):
			adapter_present = true
			if online == "1":
				adapter_online = true
		elif _BATTERY_TYPES.has(type):
			battery_present = true
			if status == "Charging":
				battery_charging = true
			elif status == "Discharging" or status == "Not charging" or status == "Full":
				battery_known = true
	# Plugged in, or the pack itself says it is taking charge.
	if adapter_online or battery_charging:
		return _SOURCE_EXTERNAL
	# A pack we can see and no adapter claiming to feed it. An offline
	# adapter is enough: the machine is unplugged even if the status file
	# could not be read.
	if battery_present and (battery_known or adapter_present):
		return _SOURCE_BATTERY
	return _SOURCE_UNKNOWN


static func _read_supplies(root: String) -> Dictionary:
	# open() on a missing directory returns null and does not log. The
	# static get_directories_at() logs an error, which a release build would
	# surface on a machine with no power_supply class.
	var dir := DirAccess.open(root)
	if dir == null:
		return {}
	var supplies := {}
	for name in dir.get_directories():
		if name.begins_with("."):
			continue
		var base := root.path_join(name)
		supplies[name] = {
			"type": _read_value(base.path_join("type")),
			"status": _read_value(base.path_join("status")),
			"online": _read_value(base.path_join("online")),
			"present": _read_value(base.path_join("present")),
		}
	return supplies


## One sysfs file. [code]get_file_as_string[/code] trusts the reported length,
## and these files report 0, so that call returns empty. Read until EOF,
## bounded so a wedged file cannot spin.
static func _read_value(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := PackedByteArray()
	while bytes.size() < _VALUE_MAX_BYTES:
		var next := file.get_8()
		if file.eof_reached():
			break
		bytes.append(next)
	return bytes.get_string_from_utf8().strip_edges()


static func _field(supply: Dictionary, key: String) -> String:
	var value: Variant = supply.get(key, "")
	if value == null or not (value is String):
		return ""
	return value.strip_edges()


static func _screen_refresh_rate() -> float:
	return DisplayServer.screen_get_refresh_rate()
