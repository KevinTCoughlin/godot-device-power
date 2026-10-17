# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerBackend
extends RefCounted

## Backend contract used by the [code]DevicePower[/code] facade.
##
## Every read has an honest default meaning "unknown". Concrete backends are
## [DevicePowerAndroidPluginBackend], [DevicePowerAndroidBackend],
## [DevicePowerNullBackend] and [DevicePowerMockBackend].
##
## A backend either is polled ([method pushes_changes] is [code]false[/code];
## reads must then be cheap) or emits [signal changed] itself.

## Emitted by a backend that [method pushes_changes] when something it
## reports may have changed. The facade then reads it again.
@warning_ignore("unused_signal")
signal changed


## Short identifier used for diagnostics, e.g. [code]"android_plugin"[/code].
func get_backend_name() -> String:
	return "abstract"


## Whether this backend emits [signal changed]. A pushing backend is polled
## only as a slow safety net ([member DevicePower.safety_poll_interval]).
func pushes_changes() -> bool:
	return false


## Asks the backend to re-read the platform now, for a backend that caches.
## Called when the app resumes or regains focus.
func request_update() -> void:
	pass


## A [code]DevicePower.PowerSource[/code] value.
func get_power_source() -> int:
	return -1


## [code]true[/code] or [code]false[/code], or [code]null[/code] when unknown.
func is_power_saver_enabled() -> Variant:
	return null


## A [code]DevicePower.GameMode[/code] value (Android's own numbering).
func get_game_mode() -> int:
	return 0


## A [code]DevicePower.ThermalStatus[/code] value (Android's own numbering),
## [code]-1[/code] when unknown.
func get_thermal_status() -> int:
	return -1


## The refresh rates the display can switch to at its current resolution,
## or an empty array when unknown.
func get_refresh_rates() -> PackedFloat32Array:
	return PackedFloat32Array()


## Asks the platform to run the game's surface at [param rate] frames per
## second ([code]0.0[/code] withdraws the request). Returns whether the
## request was made.
func vote_frame_rate(_rate: float) -> bool:
	return false
