# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends Control

## Shows what DevicePower reports and the cap it recommends, and applies it.
##
## On a desktop everything is unknown (the null backend) and the cap is 0.
## On an Android device, plug and unplug a charger, toggle battery saver or
## pick a game mode in the Game Dashboard and watch the cap follow. The
## "Menu cap" toggle stands in for a game dropping its own cap on a menu,
## which the frame rate vote follows.

const MENU_FPS := 30

var _menu := false

@onready var _state: Label = %State
@onready var _log: RichTextLabel = %Log
@onready var _fps: Label = %Fps


func _ready() -> void:
	DevicePower.changed.connect(_on_changed)
	%MenuButton.toggled.connect(_on_menu_toggled)
	%RefreshButton.pressed.connect(DevicePower.refresh)
	_on_changed()


func _process(_delta: float) -> void:
	_fps.text = "%d fps (Engine.max_fps %d)" % [Engine.get_frames_per_second(), Engine.max_fps]


func _on_changed() -> void:
	var cap = DevicePower.recommended_fps_cap(DisplayServer.screen_get_refresh_rate())
	# Checked, not trusted: in a release export a script error anywhere in the
	# call returns null, and the cap goes on into an engine property.
	if not (cap is int):
		_write("recommended_fps_cap() did not return an int: %s" % [cap])
		return
	Engine.max_fps = _tighter(cap, MENU_FPS) if _menu else cap
	var saver: Variant = DevicePower.is_power_saver_enabled()
	_state.text = (
		"\n"
		. join(
			[
				"Backend: %s" % DevicePower.get_backend_name(),
				"Power source: %s" % _key(DevicePower.PowerSource, DevicePower.get_power_source()),
				"Battery saver: %s" % ("unknown" if saver == null else str(saver)),
				"Game mode: %s" % _key(DevicePower.GameMode, DevicePower.get_game_mode()),
				(
					"Thermal status: %s"
					% _key(DevicePower.ThermalStatus, DevicePower.get_thermal_status())
				),
				(
					"Thermal back-off: %s"
					% _key(DevicePower.ThermalBackOff, DevicePower.get_thermal_back_off())
				),
				"Refresh rates: %s" % DevicePower.get_refresh_rates(),
				"Recommended cap: %s" % ("none" if cap == 0 else str(cap)),
			]
		)
	)
	_write("changed: cap %d, max_fps %d" % [cap, Engine.max_fps])


func _on_menu_toggled(on: bool) -> void:
	_menu = on
	_on_changed()


func _write(line: String) -> void:
	_log.append_text("[%s] %s\n" % [Time.get_time_string_from_system(), line])


static func _tighter(cap: int, limit: int) -> int:
	return limit if cap <= 0 else mini(cap, limit)


static func _key(enum_dict: Dictionary, value: int) -> String:
	var key: Variant = enum_dict.find_key(value)
	return str(key) if key != null else str(value)
