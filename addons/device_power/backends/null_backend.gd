# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerNullBackend
extends DevicePowerBackend

## Backend for every platform without a power bridge that is actually
## available. Windows, macOS and iOS use [DevicePowerNativeBackend] when the
## GDExtension is loaded and reports support; otherwise they land here, and
## so does everything that has no read at all. Everything is unknown, which
## the frame-cap policy treats as "impose nothing".
##
## Every read is the contract's default, so nothing is overridden but the name.


func get_backend_name() -> String:
	return "null"
