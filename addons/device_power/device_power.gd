# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends Node

## What the device's power situation is, and how fast a game should draw
## because of it.
##
## Installed as the [code]DevicePower[/code] autoload by the
## [code]device_power[/code] plugin. It polls a backend chosen at startup
## ([DevicePowerAndroidBackend] on Android, [DevicePowerNullBackend]
## elsewhere, or one injected by tests) and emits [signal changed] when
## anything it reports changes.
##
## [codeblock]
## func _ready() -> void:
##     DevicePower.changed.connect(_apply_cap)
##     _apply_cap()
##
## func _apply_cap() -> void:
##     Engine.max_fps = DevicePower.recommended_fps_cap(DisplayServer.screen_get_refresh_rate())
## [/codeblock]
##
## [b]Asking the display.[/b] With [member vote_frame_rate] on (the default),
## the addon also tells the platform the rate the game is actually running
## at: [member Engine.max_fps] when it is set, the panel's peak when it is 0.
## So a game that drops its cap on menus (say to 30) lets the panel follow.
## On Android that is [code]Surface.setFrameRate()[/code] (Android 12+). On
## a Pixel 10 with Android 16 it lifted Android's game default frame rate
## (60) for an app that stays a game, and let the panel drop to 60 Hz on
## battery. The user's peak refresh rate setting still caps it.

## Emitted after a poll finds a different power source, battery saver state
## or game mode, and once after a backend is set.
signal changed

## Where the power comes from.
enum PowerSource {
	UNKNOWN = -1,  ## No answer: no bridge on this platform, or the read failed.
	BATTERY = 0,  ## Running on the battery.
	EXTERNAL = 1,  ## On a charger, USB, a dock or wireless charging, whether or not it is charging right now.
}

## Android [code]GameManager[/code] modes, in Android's numbering.
enum GameMode {
	UNSUPPORTED = 0,  ## Not a game, before Android 12, or not Android.
	STANDARD = 1,  ## The default: the game's own policy applies.
	PERFORMANCE = 2,  ## The player asked for the smoothest play.
	BATTERY = 3,  ## The player asked to save battery.
	CUSTOM = 4,  ## OEM or adb intervention settings; treated like Standard.
}

## Seconds between polls of the power source and battery saver while the
## app is in the foreground. A charger plugged in mid-game is picked up
## within this long. The game mode is read at start and when the app
## resumes or regains focus (the Game Dashboard takes focus to change it).
@export var poll_interval: float = 2.0

## Whether to ask the platform for the rate the game runs at (see the class
## description). Off leaves the display to the platform's defaults.
@export var vote_frame_rate: bool = true

## The cap on battery or with battery saver on.
@export var battery_fps: int = 60

## The cap in the OS's Battery game mode.
@export var battery_mode_fps: int = 30

var _backend: DevicePowerBackend = null
var _power_source: int = PowerSource.UNKNOWN
var _power_saver: Variant = null
var _game_mode: int = GameMode.UNSUPPORTED
var _clock: float = 0.0
var _peak_refresh_rate: float = 0.0
var _refresh_rates := PackedFloat32Array()
## The last vote the platform accepted, or -1.0 when one is due.
var _voted: float = -1.0
## The last rate tried, so a failed vote is retried on polls, not every frame.
var _tried: float = -1.0
var _vote_logged := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _backend == null:
		set_backend(_create_default_backend())


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= poll_interval:
		refresh()
	elif _vote_target() != _tried:
		# The game changed its cap (a menu, a demo): follow it now, not on the
		# next poll. Reading the cap every frame costs nothing.
		_vote()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# A resumed app may draw into a new surface, which has no vote yet.
		_voted = -1.0
		_read(true)
		refresh()


## Replaces the backend and reads it at once. Tests inject a
## [DevicePowerMockBackend] here.
func set_backend(backend: DevicePowerBackend) -> void:
	assert(backend != null, "DevicePower.set_backend() requires a backend; use DevicePowerNullBackend.new().")
	_backend = backend
	_refresh_rates = PackedFloat32Array()
	_peak_refresh_rate = 0.0
	for rate in backend.get_refresh_rates():
		if is_finite(rate) and rate > 0.0:
			_refresh_rates.append(rate)
			_peak_refresh_rate = maxf(_peak_refresh_rate, rate)
	_voted = -1.0
	_read(true)
	_vote()
	changed.emit()


func get_backend_name() -> String:
	return _backend.get_backend_name() if _backend else "none"


## Reads the backend now; emits [signal changed] if anything differs.
func refresh() -> void:
	if not _backend:
		return
	var differs := _read(false)
	_vote()
	if differs:
		changed.emit()


## A [enum PowerSource] value, as of the last poll.
func get_power_source() -> PowerSource:
	return _power_source as PowerSource


## Battery saver, as of the last poll: [code]true[/code], [code]false[/code],
## or [code]null[/code] when unknown.
func is_power_saver_enabled() -> Variant:
	return _power_saver


## A [enum GameMode] value, as of the last poll.
func get_game_mode() -> GameMode:
	return _game_mode as GameMode


## The display's highest refresh rate, or [code]0.0[/code] when unknown.
func get_peak_refresh_rate() -> float:
	return _peak_refresh_rate


## The refresh rates the display can switch to (empty when unknown).
func get_refresh_rates() -> PackedFloat32Array:
	return _refresh_rates


## [method fps_cap] for the current state, with [member battery_fps] and
## [member battery_mode_fps], then [method paced_cap] for this display.
## [param refresh_rate] stands in for the peak refresh rate in Performance
## mode when the peak is unknown.
func recommended_fps_cap(refresh_rate: float) -> int:
	var peak := _peak_refresh_rate if _peak_refresh_rate > 0.0 else refresh_rate
	var cap := fps_cap(_power_source, _power_saver, _game_mode, peak, battery_fps, battery_mode_fps)
	return paced_cap(cap, _refresh_rates)


## The lowest frame rate at or above [param cap] that the display can show
## evenly: a rate it can switch to, or one divided by a whole number. A cap
## the panel cannot pace is rounded up, never down, so a cap never costs
## more smoothness than it asked for: 60 stays 60 on a 60/120 Hz panel,
## becomes 90 (no saving) on a panel fixed at 90 Hz, and 72 on 144 Hz; 30
## on 90 Hz stays 30. [code]0[/code] (no cap), no known rates, or a cap
## above every rate is returned as is.
static func paced_cap(cap: int, refresh_rates: PackedFloat32Array) -> int:
	if cap <= 0 or refresh_rates.is_empty():
		return cap
	var best := 0
	for rate in refresh_rates:
		if not is_finite(rate) or rate <= 0.0:
			continue
		# Display rates are not whole (59.94, 120.00001): allow half a frame.
		var divisor := maxi(1, floori((rate + 0.5) / cap))
		var paced := rate / divisor
		if paced >= cap - 0.5 and (best == 0 or roundi(paced) < best):
			best = roundi(paced)
	return best if best > 0 else cap


## The rate to ask the display for under a frame cap: the cap, or the peak
## when uncapped, or [code]0.0[/code] (withdraw the request) when neither is
## known.
static func frame_rate_vote(cap: int, peak_refresh_rate: float) -> float:
	if cap > 0:
		return float(cap)
	return maxf(peak_refresh_rate, 0.0)


## The frame cap for a power state, for [member Engine.max_fps]: 0 means
## "no cap of ours", leaving the display's refresh rate (with V-Sync) as the
## limit.
##
## [br]- An explicit OS game mode is the player's choice and wins:
##   Performance runs at [param refresh_rate] (pass the panel's peak; capped
##   at 240), Battery at [param battery_mode_fps].
## [br]- Otherwise external power is uncapped and the battery is held to
##   [param battery_fps]; battery saver counts as battery even on a charger.
## [br]- Unknown imposes nothing: a platform without a bridge keeps whatever
##   the game would do anyway.
static func fps_cap(
	power_source: int,
	power_saver: Variant,
	game_mode: int,
	refresh_rate: float,
	battery_fps: int = 60,
	battery_mode_fps: int = 30,
) -> int:
	match game_mode:
		GameMode.PERFORMANCE:
			if is_finite(refresh_rate) and refresh_rate > 0.0:
				return clampi(roundi(refresh_rate), 1, 240)
			return battery_fps
		GameMode.BATTERY:
			return battery_mode_fps
	# Only a real true counts. `==` between an int and a bool is a script
	# error, and in a release export a failed call quietly returns null.
	var saver_on: bool = power_saver is bool and power_saver
	if saver_on or power_source == PowerSource.BATTERY:
		return battery_fps
	return 0


## Reads the backend into the fields. The game mode only on [param full]
## reads: it changes through the Game Dashboard, which takes focus.
## Comparisons are type-safe on purpose: a release export turns a script
## error into a silent null, which a typed caller cannot survive.
func _read(full: bool) -> bool:
	_clock = 0.0
	var source := _backend.get_power_source()
	var raw_saver: Variant = _backend.is_power_saver_enabled()
	var saver: Variant = raw_saver if raw_saver is bool else null
	var mode := _backend.get_game_mode() if full else _game_mode
	var saver_differs: bool = typeof(saver) != typeof(_power_saver) or (saver is bool and saver != _power_saver)
	var differs: bool = source != _power_source or saver_differs or mode != _game_mode
	_power_source = source
	_power_saver = saver
	_game_mode = mode
	return differs


## What to vote: the cap the game actually runs under.
func _vote_target() -> float:
	return frame_rate_vote(Engine.max_fps, _peak_refresh_rate)


func _vote() -> void:
	if not vote_frame_rate:
		return
	var rate := _vote_target()
	if rate == _voted:
		_tried = rate
		return
	_tried = rate
	var ok := _backend.vote_frame_rate(rate)
	if ok:
		_voted = rate
	# Logged once, where there is a platform to vote to.
	if not _vote_logged and get_backend_name() != "null":
		_vote_logged = true
		print("DevicePower: frame rate vote %.1f via %s: %s" % [rate, get_backend_name(), "ok" if ok else "not made"])


func _create_default_backend() -> DevicePowerBackend:
	if OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime"):
		return DevicePowerAndroidBackend.new(Engine.get_singleton("AndroidRuntime"))
	return DevicePowerNullBackend.new()
