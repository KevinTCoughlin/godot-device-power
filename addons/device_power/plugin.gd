# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

## Installs and removes the [code]DevicePower[/code] autoload, and registers
## the export plugin that bundles the Android plugin into Android exports.

const AUTOLOAD_NAME := "DevicePower"
const AUTOLOAD_PATH := "res://addons/device_power/device_power.gd"
const ExportPlugin := preload("res://addons/device_power/export_plugin.gd")

var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	remove_autoload_singleton(AUTOLOAD_NAME)
