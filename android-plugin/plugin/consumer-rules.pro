# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT

# Godot finds the plugin class through the manifest and its @UsedByGodot
# methods through reflection; a minified game must keep both.
-keep class com.kevintcoughlin.devicepower.DevicePowerPlugin { *; }
