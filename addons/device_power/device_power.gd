# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends Node

## What the device's power situation is, and how fast a game should draw
## because of it.
##
## Installed as the [code]DevicePower[/code] autoload by the
## [code]device_power[/code] plugin. It reads a backend chosen at startup
## ([DevicePowerAndroidPluginBackend] when the Android plugin is in the
## export, [DevicePowerAndroidBackend] on Android without it,
## [DevicePowerNullBackend] elsewhere, or one injected by tests) and emits
## [signal changed] when anything it reports changes.
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
##
## [b]Heat.[/b] When the device reports thermal pressure the cap backs off
## (see [method fps_cap]). It backs off at once and recovers only after the
## status has stayed lower for [member thermal_cooldown] seconds, so a status
## that flickers at a boundary does not make the frame rate flicker too.

## Emitted when the power source, battery saver, game mode, thermal status,
## thermal back-off or refresh rates change, and once after a backend is set.
signal changed

## Where the power comes from.
enum PowerSource {
	UNKNOWN = -1,  ## No answer: no bridge on this platform, or the read failed.
	BATTERY = 0,  ## Running on the battery.
	## On a charger, USB, a dock or wireless charging, whether or not it is
	## charging right now.
	EXTERNAL = 1,
}

## Android [code]GameManager[/code] modes, in Android's numbering.
enum GameMode {
	UNSUPPORTED = 0,  ## Not a game, before Android 12, or not Android.
	STANDARD = 1,  ## The default: the game's own policy applies.
	PERFORMANCE = 2,  ## The player asked for the smoothest play.
	BATTERY = 3,  ## The player asked to save battery.
	CUSTOM = 4,  ## OEM or adb intervention settings; treated like Standard.
}

## Android [code]PowerManager.THERMAL_STATUS_*[/code], in Android's numbering.
enum ThermalStatus {
	UNKNOWN = -1,  ## No answer: before Android 10, not Android, or the read failed.
	NONE = 0,  ## Not under thermal pressure.
	LIGHT = 1,  ## Light throttling, without noticeable impact on the experience.
	MODERATE = 2,  ## Moderate throttling, with some impact.
	SEVERE = 3,  ## Severe throttling; the experience is largely affected.
	CRITICAL = 4,  ## The platform has done everything it can to reduce power.
	EMERGENCY = 5,  ## Key components are shutting down.
	SHUTDOWN = 6,  ## The device is about to shut down.
}

## How far heat holds the cap down; see [method thermal_back_off].
enum ThermalBackOff {
	NONE = 0,  ## No thermal limit.
	MODERATE = 1,  ## Capped at [member battery_fps] at most.
	SEVERE = 2,  ## Capped at [member battery_mode_fps] at most.
}

## The engine singleton the Android plugin registers.
const ANDROID_PLUGIN_SINGLETON := "DevicePowerAndroid"
## A status that stands for each back-off, for [method fps_cap].
const _BACK_OFF_STATUS: Array[int] = [
	ThermalStatus.NONE,
	ThermalStatus.MODERATE,
	ThermalStatus.SEVERE,
]

## Seconds between polls of a polled backend (the [JavaClassWrapper]
## fallback) while the app is in the foreground. A charger plugged in
## mid-game is picked up within this long. The game mode is read at start
## and when the app resumes or regains focus (the Game Dashboard takes focus
## to change it).
@export var poll_interval: float = 2.0

## Seconds between safety reads of a backend that pushes its changes (the
## Android plugin), in case a notification is ever missed. Reads of the
## plugin cost no system call. [code]0[/code] turns the safety read off.
@export var safety_poll_interval: float = 30.0

## Whether to ask the platform for the rate the game runs at (see the class
## description). Off leaves the display to the platform's defaults.
@export var vote_frame_rate: bool = true

## The cap on battery or with battery saver on, and the most that moderate
## thermal pressure allows.
@export var battery_fps: int = 60

## The cap in the OS's Battery game mode, and the most that severe thermal
## pressure allows.
@export var battery_mode_fps: int = 30

## Seconds the thermal status must stay below the current back-off before
## the cap recovers. Backing off is immediate.
@export var thermal_cooldown: float = 30.0

var _backend: DevicePowerBackend = null
var _power_source: int = PowerSource.UNKNOWN
var _power_saver: Variant = null
var _game_mode: int = GameMode.UNSUPPORTED
var _thermal_status: int = ThermalStatus.UNKNOWN
## The back-off in force, after hysteresis.
var _back_off: int = ThermalBackOff.NONE
## When the status first dropped below [member _back_off], or -1.0.
var _cooling_since: float = -1.0
## The highest back-off the status asked for since [member _cooling_since].
var _cooling_peak: int = ThermalBackOff.NONE
## Seconds since the last poll.
var _since_poll: float = 0.0
var _peak_refresh_rate: float = 0.0
var _refresh_rates := PackedFloat32Array()
## The last vote the platform accepted, or -1.0 when one is due.
var _voted: float = -1.0
## The last rate tried, so a failed vote is retried on polls, not every frame.
var _tried: float = -1.0
var _vote_logged := false
## Returns the time in seconds; tests replace it with a fake clock.
var _clock: Callable = _ticks_seconds


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _backend == null:
		set_backend(select_backend(OS.get_name(), _engine_singleton))


func _process(delta: float) -> void:
	_since_poll += delta
	var interval := (
		safety_poll_interval if _backend and _backend.pushes_changes() else poll_interval
	)
	if interval > 0.0 and _since_poll >= interval:
		refresh()
		return
	if _cooling_since >= 0.0 and _update_back_off():
		changed.emit()
	if _vote_target() != _tried:
		# The game changed its cap (a menu, a demo): follow it now, not on the
		# next poll. Reading the cap every frame costs nothing.
		_vote()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not _backend:
			return
		# A resumed app may draw into a new surface, which has no vote yet.
		_voted = -1.0
		_backend.request_update()
		var differs := _read(true)
		_vote()
		if differs:
			changed.emit()


## Replaces the backend and reads it at once. Tests inject a
## [DevicePowerMockBackend] here.
func set_backend(backend: DevicePowerBackend) -> void:
	assert(
		backend != null,
		"DevicePower.set_backend() requires a backend; use DevicePowerNullBackend.new()."
	)
	if _backend and _backend.changed.is_connected(_on_backend_changed):
		_backend.changed.disconnect(_on_backend_changed)
	_backend = backend
	_backend.changed.connect(_on_backend_changed)
	_back_off = ThermalBackOff.NONE
	_cooling_since = -1.0
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


## A [enum PowerSource] value, as of the last read.
func get_power_source() -> PowerSource:
	return _power_source as PowerSource


## Battery saver, as of the last read: [code]true[/code], [code]false[/code],
## or [code]null[/code] when unknown.
func is_power_saver_enabled() -> Variant:
	return _power_saver


## A [enum GameMode] value, as of the last read.
func get_game_mode() -> GameMode:
	return _game_mode as GameMode


## A [enum ThermalStatus] value, as of the last read.
func get_thermal_status() -> ThermalStatus:
	return _thermal_status as ThermalStatus


## The [enum ThermalBackOff] in force, after [member thermal_cooldown].
func get_thermal_back_off() -> ThermalBackOff:
	return _back_off as ThermalBackOff


## The display's highest refresh rate, or [code]0.0[/code] when unknown.
func get_peak_refresh_rate() -> float:
	return _peak_refresh_rate


## The refresh rates the display can switch to (empty when unknown).
func get_refresh_rates() -> PackedFloat32Array:
	return _refresh_rates


## [method fps_cap] for the current state, with [member battery_fps],
## [member battery_mode_fps] and the thermal back-off in force, paced to this
## display by [method paced_fps_cap]: a power or game-mode cap rounds up to
## an even rate, a thermal cap rounds down, and heat wins.
## [param refresh_rate] stands in for the peak refresh rate in Performance
## mode when the peak is unknown.
func recommended_fps_cap(refresh_rate: float) -> int:
	var peak := _peak_refresh_rate if _peak_refresh_rate > 0.0 else refresh_rate
	var cap := _power_cap(
		_power_source, _power_saver, _game_mode, peak, battery_fps, battery_mode_fps
	)
	var limit := thermal_limit(_BACK_OFF_STATUS[_back_off], battery_fps, battery_mode_fps)
	return paced_fps_cap(cap, limit, _refresh_rates)


## The backend for a platform: [param os_name] as [method OS.get_name]
## reports it, and [param get_singleton] a [Callable] taking a singleton
## name and returning the [Object] or [code]null[/code].
static func select_backend(os_name: String, get_singleton: Callable) -> DevicePowerBackend:
	if os_name != "Android":
		return DevicePowerNullBackend.new()
	var plugin: Variant = get_singleton.call(ANDROID_PLUGIN_SINGLETON)
	if plugin is Object and plugin != null:
		var backend := DevicePowerAndroidPluginBackend.new(plugin)
		if backend.is_compatible():
			return backend
		push_warning(
			(
				"DevicePower: the %s plugin speaks another API; falling back."
				% ANDROID_PLUGIN_SINGLETON
			)
		)
	var runtime: Variant = get_singleton.call("AndroidRuntime")
	if runtime is Object and runtime != null:
		return DevicePowerAndroidBackend.new(runtime)
	return DevicePowerNullBackend.new()


## The lowest frame rate at or above [param cap] that the display can show
## evenly: a rate it can switch to, or one divided by a whole number. A cap
## the panel cannot pace is rounded up, never down, so a power or game-mode
## cap never costs more smoothness than it asked for: 60 stays 60 on a
## 60/120 Hz panel, becomes 90 (no saving) on a panel fixed at 90 Hz, and 72
## on 144 Hz; 30 on 90 Hz stays 30. [code]0[/code] (no cap), no known rates,
## or a cap above every rate is returned as is. Thermal caps use
## [method paced_cap_down] instead.
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


## The highest frame rate at or below [param cap] that the display can show
## evenly: a rate it can switch to, or one divided by a whole number. Used
## for thermal caps, where the point is to shed heat, so the cap is never
## exceeded: 60 becomes 45 on a panel fixed at 90 Hz, stays 60 on 60/120 Hz,
## and becomes 48 on 144 Hz; 30 on 90 Hz stays 30. [code]0[/code] (no cap)
## or no known rates is returned as is.
static func paced_cap_down(cap: int, refresh_rates: PackedFloat32Array) -> int:
	if cap <= 0 or refresh_rates.is_empty():
		return cap
	var best := 0
	for rate in refresh_rates:
		if not is_finite(rate) or rate <= 0.0:
			continue
		# Half a frame of slack, as in paced_cap(): 59.94 Hz paces a 60 cap.
		var divisor := maxi(1, ceili((rate - 0.5) / cap))
		var paced := roundi(rate / divisor)
		if paced >= 1 and paced <= cap and paced > best:
			best = paced
	return best if best > 0 else cap


## The cap to apply for a power cap [param cap] (from [method fps_cap]
## without heat; [code]0[/code] is none) and a thermal limit [param limit]
## (from [method thermal_limit]; [code]0[/code] is none), paced to
## [param refresh_rates]. The power cap rounds up ([method paced_cap]), the
## thermal limit rounds down ([method paced_cap_down]), and the result never
## exceeds the paced thermal limit: heat wins.
static func paced_fps_cap(cap: int, limit: int, refresh_rates: PackedFloat32Array) -> int:
	var paced := paced_cap(cap, refresh_rates)
	if limit <= 0:
		return paced
	return _tighter(paced, paced_cap_down(limit, refresh_rates))


## The most a [enum ThermalStatus] allows: [param battery_fps] from
## Moderate, [param battery_mode_fps] from Severe, [code]0[/code] (no
## limit) below Moderate or when unknown.
static func thermal_limit(
	thermal_status: int, battery_fps: int = 60, battery_mode_fps: int = 30
) -> int:
	match thermal_back_off(thermal_status):
		ThermalBackOff.SEVERE:
			return maxi(battery_mode_fps, 0)
		ThermalBackOff.MODERATE:
			return maxi(battery_fps, 0)
	return 0


## The rate to ask the display for under a frame cap: the cap, or the peak
## when uncapped, or [code]0.0[/code] (withdraw the request) when neither is
## known.
static func frame_rate_vote(cap: int, peak_refresh_rate: float) -> float:
	if cap > 0:
		return float(cap)
	return maxf(peak_refresh_rate, 0.0)


## The [enum ThermalBackOff] a [enum ThermalStatus] calls for: none below
## Moderate, Moderate for Moderate, Severe from Severe up. Light throttling
## is left to the platform; unknown imposes nothing.
static func thermal_back_off(thermal_status: int) -> int:
	if thermal_status >= ThermalStatus.SEVERE:
		return ThermalBackOff.SEVERE
	if thermal_status >= ThermalStatus.MODERATE:
		return ThermalBackOff.MODERATE
	return ThermalBackOff.NONE


## The frame cap for a power state, for [member Engine.max_fps]: 0 means
## "no cap of ours", leaving the display's refresh rate (with V-Sync) as the
## limit.
##
## [br]- An explicit OS game mode is the player's choice and wins over the
##   power source: Performance runs at [param refresh_rate] (pass the panel's
##   peak; capped at 240), Battery at [param battery_mode_fps].
## [br]- Otherwise external power is uncapped and the battery is held to
##   [param battery_fps]; battery saver counts as battery even on a charger.
## [br]- Unknown imposes nothing: a platform without a bridge keeps whatever
##   the game would do anyway.
## [br]- Heat wins over everything, Performance mode included: at
##   [param thermal_status] Moderate the cap is at most [param battery_fps],
##   from Severe at most [param battery_mode_fps]. An uncapped game gets that
##   cap. These thresholds are a starting point: calibrate them on your
##   game's hottest scene and target devices.
##
## This is the cap before pacing; [method paced_fps_cap] paces it to a
## display, rounding a thermal limit down and any other cap up.
static func fps_cap(
	power_source: int,
	power_saver: Variant,
	game_mode: int,
	refresh_rate: float,
	battery_fps: int = 60,
	battery_mode_fps: int = 30,
	thermal_status: int = ThermalStatus.UNKNOWN,
) -> int:
	var cap := _power_cap(
		power_source, power_saver, game_mode, refresh_rate, battery_fps, battery_mode_fps
	)
	return _tighter(cap, thermal_limit(thermal_status, battery_fps, battery_mode_fps))


static func _power_cap(
	power_source: int,
	power_saver: Variant,
	game_mode: int,
	refresh_rate: float,
	battery_fps: int,
	battery_mode_fps: int,
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


## The tighter of two caps, where 0 is no cap.
static func _tighter(cap: int, limit: int) -> int:
	if limit <= 0:
		return cap
	if cap <= 0:
		return limit
	return mini(cap, limit)


## Reads the backend into the fields. A polled backend's game mode is read
## only on [param full] reads: it changes through the Game Dashboard, which
## takes focus. Comparisons are type-safe on purpose: a release export turns
## a script error into a silent null, which a typed caller cannot survive.
func _read(full: bool) -> bool:
	_since_poll = 0.0
	var source := _backend.get_power_source()
	if source < PowerSource.UNKNOWN or source > PowerSource.EXTERNAL:
		source = PowerSource.UNKNOWN
	var raw_saver: Variant = _backend.is_power_saver_enabled()
	var saver: Variant = raw_saver if raw_saver is bool else null
	var mode := _game_mode
	if full or _backend.pushes_changes():
		mode = _backend.get_game_mode()
		if mode < GameMode.UNSUPPORTED or mode > GameMode.CUSTOM:
			mode = GameMode.UNSUPPORTED
	var thermal := _backend.get_thermal_status()
	if thermal < ThermalStatus.UNKNOWN or thermal > ThermalStatus.SHUTDOWN:
		thermal = ThermalStatus.UNKNOWN
	var saver_differs: bool = (
		typeof(saver) != typeof(_power_saver) or (saver is bool and saver != _power_saver)
	)
	var differs: bool = (
		source != _power_source or saver_differs or mode != _game_mode or thermal != _thermal_status
	)
	_power_source = source
	_power_saver = saver
	_game_mode = mode
	_thermal_status = thermal
	if _update_back_off():
		differs = true
	if full or _backend.pushes_changes():
		if _read_refresh_rates():
			differs = true
	return differs


## Applies hysteresis to the thermal back-off. Returns whether it changed.
func _update_back_off() -> bool:
	var wanted := thermal_back_off(_thermal_status)
	var before := _back_off
	if wanted >= _back_off:
		_back_off = wanted
		_cooling_since = -1.0
		return _back_off != before
	var now: float = _clock.call()
	if _cooling_since < 0.0:
		_cooling_since = now
		_cooling_peak = wanted
	else:
		_cooling_peak = maxi(_cooling_peak, wanted)
	if now - _cooling_since < thermal_cooldown:
		return false
	# Below the back-off for long enough: step down to the highest level asked
	# for meanwhile, and keep cooling if the status is lower still.
	_back_off = _cooling_peak
	_cooling_since = now if wanted < _back_off else -1.0
	_cooling_peak = wanted
	return _back_off != before


## Reads the refresh rates. Returns whether they changed.
func _read_refresh_rates() -> bool:
	var rates := PackedFloat32Array()
	var peak := 0.0
	for rate in _backend.get_refresh_rates():
		if is_finite(rate) and rate > 0.0:
			rates.append(rate)
			peak = maxf(peak, rate)
	if rates == _refresh_rates:
		return false
	_refresh_rates = rates
	_peak_refresh_rate = peak
	return true


## What to vote: the cap the game actually runs under.
func _vote_target() -> float:
	return frame_rate_vote(Engine.max_fps, _peak_refresh_rate)


func _vote() -> void:
	if not vote_frame_rate or not _backend:
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
		print(
			(
				"DevicePower: frame rate vote %.1f via %s: %s"
				% [rate, get_backend_name(), "ok" if ok else "not made"]
			)
		)


func _on_backend_changed() -> void:
	refresh()


static func _engine_singleton(singleton_name: String) -> Object:
	return Engine.get_singleton(singleton_name) if Engine.has_singleton(singleton_name) else null


static func _ticks_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
