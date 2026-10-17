# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
@tool
extends EditorExportPlugin

## Bundles the [code]DevicePowerAndroid[/code] plugin (an AAR) into Android
## exports, using Godot's Android plugin v2 export hooks (Godot 4.2+).
##
## AARs are only linked by a Gradle build: enable
## [code]gradle_build/use_gradle_build[/code] in the Android export preset.
## Without a Gradle build, or without the AARs in [code]bin/[/code] (a source
## checkout that has not run [code]scripts/build_android.sh[/code]), nothing
## is bundled and the addon falls back to [DevicePowerAndroidBackend] at run
## time, which needs no Java code of its own.

const PLUGIN_NAME := "DevicePowerAndroid"
## Relative to res://addons/, as _get_android_libraries() requires.
const DEBUG_AAR := "device_power/bin/debug/device_power-debug.aar"
const RELEASE_AAR := "device_power/bin/release/device_power-release.aar"

var _warned := false


func _get_name() -> String:
	return PLUGIN_NAME


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var libraries := android_libraries(debug)
	if libraries.is_empty() and not _warned:
		_warned = true
		push_warning(
			(
				(
					"Device Power: %s is missing, so the Android plugin is not bundled and the"
					+ " JavaClassWrapper fallback will be used. Run scripts/build_android.sh,"
					+ " or install the addon from a release archive."
				)
				% aar_path(debug)
			)
		)
	return libraries


## The AARs to bundle into a debug or release export, relative to
## res://addons/: the one built for it, or none when it has not been built.
static func android_libraries(debug: bool) -> PackedStringArray:
	var aar := aar_path(debug)
	if not FileAccess.file_exists("res://addons/" + aar):
		return PackedStringArray()
	return PackedStringArray([aar])


## The AAR for a debug or release export, relative to res://addons/.
static func aar_path(debug: bool) -> String:
	return DEBUG_AAR if debug else RELEASE_AAR
