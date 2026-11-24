# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerNullBackend
extends DevicePowerBackend

## Backend for platforms without a power bridge: Windows, macOS, iOS and the
## web. Godot 4 has no power API on those, and there is no portable file or
## call this addon can make. Everything is unknown, which the frame-cap
## policy treats as "impose nothing". Linux is [DevicePowerLinuxBackend].
##
## Every read is the contract's default, so nothing is overridden but the name.


func get_backend_name() -> String:
	return "null"
