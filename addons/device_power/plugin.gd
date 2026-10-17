# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

## Installs and removes the [code]DevicePower[/code] autoload, and registers
## the export plugin that bundles the Android plugin into Android exports.
##
## The autoload is added and removed only when the plugin is enabled or
## disabled in Project Settings ([method _enable_plugin],
## [method _disable_plugin]). Doing it in [method _enter_tree] and
## [method _exit_tree] would rewrite [code]project.godot[/code] on every
## editor start, headless import and export: stripping its comments, and
## dropping the autoload again whenever the editor quits.

const AUTOLOAD_NAME := "DevicePower"
const AUTOLOAD_PATH := "res://addons/device_power/device_power.gd"
const ExportPlugin := preload("res://addons/device_power/export_plugin.gd")

var _export_plugin: EditorExportPlugin = null


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
