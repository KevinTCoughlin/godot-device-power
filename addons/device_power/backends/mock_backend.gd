# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerMockBackend
extends DevicePowerBackend

## Scriptable backend for tests: set the fields, then call
## [code]DevicePower.refresh()[/code].

var power_source: int = -1
var power_saver: Variant = null
var game_mode: int = 0
var refresh_rates: PackedFloat32Array = PackedFloat32Array()
## Whether [method vote_frame_rate] succeeds, as a missing surface would not.
var vote_ok: bool = true
## Every rate passed to [method vote_frame_rate], oldest first.
var votes: Array[float] = []


func get_backend_name() -> String:
	return "mock"


func get_power_source() -> int:
	return power_source


func is_power_saver_enabled() -> Variant:
	return power_saver


func get_game_mode() -> int:
	return game_mode


func get_refresh_rates() -> PackedFloat32Array:
	return refresh_rates


func vote_frame_rate(rate: float) -> bool:
	votes.append(rate)
	return vote_ok
