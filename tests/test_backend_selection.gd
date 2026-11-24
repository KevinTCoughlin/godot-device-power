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


func test_linux_reads_sysfs_and_other_desktops_get_the_null_backend() -> void:
	var linux: DevicePowerBackend = Facade.select_backend("Linux", _lookup({}))
	assert_eq(linux.get_backend_name(), "linux")
	for os_name: String in ["Windows", "macOS", "iOS", "Web", "FreeBSD"]:
		var backend: DevicePowerBackend = Facade.select_backend(os_name, _lookup({}))
		assert_eq(backend.get_backend_name(), "null", os_name)


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


func test_an_unknown_os_or_a_missing_lookup_stays_unknown() -> void:
	for os_name: String in ["", "Steam", "UWP"]:
		var backend: DevicePowerBackend = Facade.select_backend(os_name, _lookup({}))
		assert_eq(backend.get_backend_name(), "null", os_name)
		assert_eq(backend.get_power_source(), -1, os_name)
		assert_null(backend.is_power_saver_enabled(), os_name)
	var blind: DevicePowerBackend = Facade.select_backend("Android", Callable())
	assert_eq(blind.get_backend_name(), "null", "Android with no lookup")


func test_a_non_object_singleton_is_ignored() -> void:
	var backend: DevicePowerBackend = Facade.select_backend(
		"Android", func(singleton_name: String) -> Variant: return 1 if singleton_name else null
	)
	assert_eq(backend.get_backend_name(), "null")
