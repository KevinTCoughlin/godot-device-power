# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends DevicePowerTestCase

## Which backend a platform gets, through select_backend() with a fake
## singleton lookup.

const Facade := DevicePowerTestCase.FACADE_SCRIPT
const FakePlugin := preload("res://tests/fake_plugin.gd")


func _lookup(singletons: Dictionary) -> Callable:
	return func(singleton_name: String) -> Object: return singletons.get(singleton_name)


func test_linux_reads_sysfs_and_unbridged_platforms_stay_null() -> void:
	var linux: DevicePowerBackend = Facade.select_backend("Linux", _lookup({}))
	assert_eq(linux.get_backend_name(), "linux")
	for os_name: String in ["Web", "FreeBSD"]:
		var backend: DevicePowerBackend = Facade.select_backend(os_name, _lookup({}))
		assert_eq(backend.get_backend_name(), "null", os_name)
	# Windows, macOS and iOS use the GDExtension only when this process can
	# read them. The Linux binary reports unsupported, so they stay null here.
	for os_name: String in ["Windows", "macOS", "iOS"]:
		var desktop: DevicePowerBackend = Facade.select_backend(os_name, _lookup({}))
		assert_eq(desktop.get_backend_name(), "null", os_name)


func test_android_prefers_the_plugin() -> void:
	var plugin := FakePlugin.new()
	var runtime := RefCounted.new()
	var backend: DevicePowerBackend = Facade.select_backend(
		"Android", _lookup({"DevicePowerAndroid": plugin, "AndroidRuntime": runtime})
	)
	assert_eq(backend.get_backend_name(), "android_plugin")
	plugin.free()


func test_android_without_any_bridge_gets_the_null_backend() -> void:
	var backend: DevicePowerBackend = Facade.select_backend("Android", _lookup({}))
	assert_eq(backend.get_backend_name(), "null")


func test_an_incompatible_plugin_is_not_used() -> void:
	var plugin := FakePlugin.new()
	plugin.api_version = 99
	var backend: DevicePowerBackend = Facade.select_backend(
		"Android", _lookup({"DevicePowerAndroid": plugin})
	)
	assert_eq(backend.get_backend_name(), "null", "nothing else to fall back to here")
	plugin.free()


func test_android_without_the_plugin_gets_the_fallback() -> void:
	var runtime := RefCounted.new()
	var backend: DevicePowerBackend = Facade.select_backend(
		"Android", _lookup({"AndroidRuntime": runtime})
	)
	assert_eq(backend.get_backend_name(), "android")


func test_an_incompatible_plugin_falls_back_to_the_runtime() -> void:
	var plugin := FakePlugin.new()
	plugin.api_version = 99
	var runtime := RefCounted.new()
	var backend: DevicePowerBackend = Facade.select_backend(
		"Android", _lookup({"DevicePowerAndroid": plugin, "AndroidRuntime": runtime})
	)
	assert_eq(backend.get_backend_name(), "android")
	plugin.free()


func test_a_non_object_singleton_is_ignored() -> void:
	var backend: DevicePowerBackend = Facade.select_backend(
		"Android", func(singleton_name: String) -> Variant: return 1 if singleton_name else null
	)
	assert_eq(backend.get_backend_name(), "null")
