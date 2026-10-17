# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerAndroidBackend
extends DevicePowerBackend

## Reads Android's power state through [JavaClassWrapper], with no Java code
## of its own to build or ship.
##
## This is the fallback: [DevicePowerAndroidPluginBackend] is used instead
## whenever the [code]DevicePowerAndroid[/code] plugin is in the export (a
## Gradle build with this addon enabled). This one is polled, and reads the
## game mode only when the facade asks for a full read.
##
## [b]Power source[/b] comes from the sticky [code]ACTION_BATTERY_CHANGED[/code]
## broadcast ([code]registerReceiver(null, filter)[/code] returns the last one
## without registering anything). Its [code]plugged[/code] extra is the right
## question: [code]BatteryManager.isCharging()[/code] turns false on a full or
## charge-limited battery that is still on the charger. It also follows
## [code]adb shell dumpsys battery unplug[/code], which makes the battery path
## testable on a device that has to stay on USB.
##
## [b]Game mode[/b] is [code]GameManager.getGameMode()[/code] (API 31+). It
## reports [code]UNSUPPORTED[/code] unless the app is classified as a game
## ([code]android:appCategory="game"[/code]).
##
## [b]Thermal status[/b] is [code]PowerManager.getCurrentThermalStatus()[/code]
## (API 29+), read on every poll.
##
## [b]Frame rate vote[/b] is [code]Surface.setFrameRate()[/code] (API 31+) on
## Godot's render surface, with [code]CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS[/code]
## so a change of plan mid-game (a charger, a menu) never blanks the screen
## for a mode switch. It is how a game asks for more than Android's game
## default frame rate while staying a game, and how it lets the panel drop to
## a lower rate. The user's peak refresh rate setting still caps it.
##
## Every Java call is checked with [method JavaClassWrapper.get_exception]; a
## failure reads as "unknown", never as a guess.

# Every Java call can fail, and each failure is an early "unknown" return, so
# the readers here have more returns than gdlint's default allows.
# gdlint: disable=max-returns

const _BATTERY_CHANGED := "android.intent.action.BATTERY_CHANGED"
const _FRAME_RATE_COMPATIBILITY_DEFAULT := 0
const _CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS := 0

var _runtime: Object
var _sdk: int = 0
var _filter: Object = null
var _power_manager: Object = null
var _game_manager: Object = null


func _init(runtime: Object) -> void:
	_runtime = runtime
	var version = JavaClassWrapper.wrap("android.os.Build$VERSION")
	if _ok() and version:
		_sdk = version.SDK_INT


func get_backend_name() -> String:
	return "android"


func get_power_source() -> int:
	var context = _context()
	if context == null:
		return -1
	if _filter == null:
		var intent_filter = JavaClassWrapper.wrap("android.content.IntentFilter")
		if not _ok() or not intent_filter:
			return -1
		_filter = intent_filter.IntentFilter(_BATTERY_CHANGED)
		if not _ok():
			_filter = null
			return -1
	var status = context.registerReceiver(null, _filter)
	if not _ok() or status == null:
		return -1
	var plugged = status.getIntExtra("plugged", -1)
	if not _ok() or not (plugged is int) or plugged < 0:
		return -1
	# 0 is on battery; AC, USB, wireless and dock are all bit flags above it.
	return 1 if plugged > 0 else 0


func is_power_saver_enabled() -> Variant:
	var power = _service("power")
	if power == null:
		return null
	var saver = power.isPowerSaveMode()
	if not _ok():
		return null
	# The wrapper hands a Java boolean back as an int; the contract is a bool.
	if saver is bool:
		return saver
	if saver is int:
		return saver != 0
	return null


func get_game_mode() -> int:
	if _sdk < 31:
		return 0
	var manager = _service("game")
	if manager == null:
		return 0
	var mode = manager.getGameMode()
	if not _ok() or not (mode is int) or mode < 0 or mode > 4:
		return 0
	return mode


func get_thermal_status() -> int:
	if _sdk < 29:
		return -1
	var power = _service("power")
	if power == null:
		return -1
	var status = power.getCurrentThermalStatus()
	if not _ok() or not (status is int) or status < 0 or status > 6:
		return -1
	return status


func get_refresh_rates() -> PackedFloat32Array:
	var rates := PackedFloat32Array()
	var activity = _runtime.getActivity()
	if not _ok() or not activity or _sdk < 30:
		return rates
	var display = activity.getDisplay()
	if not _ok() or not display:
		return rates
	var current = display.getMode()
	var modes = display.getSupportedModes()
	if not _ok() or not current or modes == null:
		return rates
	var width = current.getPhysicalWidth()
	var height = current.getPhysicalHeight()
	if not _ok() or width == null or height == null:
		return rates
	for mode in modes:
		if mode == null:
			continue
		var w = mode.getPhysicalWidth()
		var h = mode.getPhysicalHeight()
		var r = mode.getRefreshRate()
		if not _ok() or w == null or h == null or r == null:
			return PackedFloat32Array()
		if int(w) != int(width) or int(h) != int(height):
			continue
		if float(r) > 0.0:
			rates.append(float(r))
		# A panel can also run a mode at lower rates it switches to seamlessly.
		# Only what apps are told counts: a Galaxy A16 lists 60 as an
		# alternative of its one 90 Hz mode in dumpsys, but apps get none.
		if _sdk >= 31:
			var alternatives = mode.getAlternativeRefreshRates()
			if not _ok():
				return PackedFloat32Array()
			if alternatives != null:
				for alt in alternatives:
					if float(alt) > 0.0 and not rates.has(float(alt)):
						rates.append(float(alt))
	return rates


func vote_frame_rate(rate: float) -> bool:
	if _sdk < 31:
		return false
	var surface = _surface()
	if surface == null:
		return false
	surface.setFrameRate(
		rate, _FRAME_RATE_COMPATIBILITY_DEFAULT, _CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
	)
	return _ok()


## Godot's render surface, or null before it exists or after it is gone.
func _surface() -> Object:
	var context = _context()
	if context == null:
		return null
	var godot_class = JavaClassWrapper.wrap("org.godotengine.godot.Godot")
	if not _ok() or not godot_class:
		return null
	var godot = godot_class.getInstance(context)
	if not _ok() or not godot:
		return null
	var render_view = godot.getRenderView()
	if not _ok() or not render_view:
		return null
	var view = render_view.getView()
	if not _ok() or not view:
		return null
	var holder = view.getHolder()
	if not _ok() or not holder:
		return null
	var surface = holder.getSurface()
	if not _ok() or not surface or not surface.isValid():
		return null
	return surface


## A system service, fetched once.
func _service(name: String) -> Object:
	var cached: Object = _power_manager if name == "power" else _game_manager
	if cached:
		return cached
	var context = _context()
	if context == null:
		return null
	var service = context.getSystemService(name)
	if not _ok() or not service:
		return null
	if name == "power":
		_power_manager = service
	else:
		_game_manager = service
	return service


func _context() -> Object:
	var context = _runtime.getApplicationContext()
	return context if _ok() and context else null


func _ok() -> bool:
	return JavaClassWrapper.get_exception() == null
