# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends Object

## Stands in for the DevicePowerAndroid engine singleton: the same method
## names (camelCase, as Kotlin declares them) and signals. Each answer is a
## field, so a test can hand the backend the wrong type on purpose.

var api_version: Variant = 1
var power_source: Variant = -1
var power_saver: Variant = -1
var game_mode: Variant = 0
var thermal_status: Variant = -1
var refresh_rates: Variant = PackedFloat32Array()
var vote_result: Variant = true
var votes: Array = []
var refreshes: int = 0


func _init() -> void:
	add_user_signal(
		"power_changed", [{"name": "source", "type": TYPE_INT}, {"name": "saver", "type": TYPE_INT}]
	)
	add_user_signal("game_mode_changed", [{"name": "mode", "type": TYPE_INT}])
	add_user_signal("thermal_status_changed", [{"name": "status", "type": TYPE_INT}])
	add_user_signal("refresh_rates_changed")


# gdlint: disable=function-name
func getApiVersion() -> Variant:
	return api_version


func getPowerSource() -> Variant:
	return power_source


func getPowerSaver() -> Variant:
	return power_saver


func getGameMode() -> Variant:
	return game_mode


func getThermalStatus() -> Variant:
	return thermal_status


func getRefreshRates() -> Variant:
	return refresh_rates


func voteFrameRate(rate: float) -> Variant:
	votes.append(rate)
	return vote_result


func refresh() -> void:
	refreshes += 1
# gdlint: enable=function-name
