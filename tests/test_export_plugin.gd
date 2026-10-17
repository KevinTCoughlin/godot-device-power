# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## The editor side: the export plugin and the editor plugin load, and the
## export plugin names the AARs only when they are there.

const ExportPlugin := preload("res://addons/device_power/export_plugin.gd")


func test_the_scripts_load() -> void:
	for path: String in [
		"res://addons/device_power/export_plugin.gd", "res://addons/device_power/plugin.gd"
	]:
		var script: Script = load(path)
		assert_true(script != null and script.can_instantiate(), path)


# EditorExportPlugin can only be instantiated inside the editor, so the
# hooks are thin wrappers over static functions, which are tested here.
# scripts/check.sh also starts the editor headlessly to load the plugin.
func test_names_and_paths() -> void:
	assert_eq(ExportPlugin.PLUGIN_NAME, "DevicePowerAndroid")
	assert_eq(ExportPlugin.aar_path(true), "device_power/bin/debug/device_power-debug.aar")
	assert_eq(ExportPlugin.aar_path(false), "device_power/bin/release/device_power-release.aar")


func test_libraries_are_listed_only_when_built() -> void:
	for debug: bool in [true, false]:
		var aar: String = ExportPlugin.aar_path(debug)
		var expected := PackedStringArray()
		if FileAccess.file_exists("res://addons/" + aar):
			expected.append(aar)
		assert_eq(ExportPlugin.android_libraries(debug), expected, "debug=%s" % debug)


func test_the_plugin_name_matches_the_kotlin_singleton() -> void:
	var kotlin := (
		FileAccess
		. get_file_as_string(
			"res://android-plugin/plugin/src/main/kotlin/com/kevintcoughlin/devicepower/DevicePowerPlugin.kt"
		)
	)
	var manifest := FileAccess.get_file_as_string(
		"res://android-plugin/plugin/src/main/AndroidManifest.xml"
	)
	if kotlin.is_empty() or manifest.is_empty():
		fail("android-plugin/ sources not found next to the project")
		return
	assert_true(kotlin.contains('const val NAME = "DevicePowerAndroid"'), "Kotlin NAME")
	assert_true(manifest.contains("org.godotengine.plugin.v2.DevicePowerAndroid"), "manifest entry")
	assert_true(
		kotlin.contains("const val API_VERSION = %d" % DevicePowerAndroidPluginBackend.API_VERSION),
		"API version"
	)
	assert_eq(
		DevicePowerAndroidPluginBackend.SINGLETON_NAME,
		DevicePowerTestCase.FACADE_SCRIPT.ANDROID_PLUGIN_SINGLETON
	)
