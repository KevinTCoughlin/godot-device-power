# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
extends SceneTree

## Deterministic, mock-backed test runner.
##
## Run it with:
## [codeblock]
## godot --headless --path . --script res://tests/run_tests.gd
## [/codeblock]
## The process exits with 0 when every test passes and 1 otherwise.
##
## A script error does not change Godot's exit code, and it silently ends the
## function it happens in, so a test that stops half-way would otherwise
## pass. The runner installs a [Logger] and fails any test during which an
## error was logged, unless the test declared it with
## [method DevicePowerTestCase.expect_errors].

const SUITES: Array[String] = [
	"res://tests/test_policy.gd",
	"res://tests/test_facade.gd",
	"res://tests/test_thermal.gd",
	"res://tests/test_android_plugin_backend.gd",
	"res://tests/test_backend_selection.gd",
	"res://tests/test_export_plugin.gd",
]


func _initialize() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var passed: int = 0
	var failed: int = 0
	var failure_log: PackedStringArray = []

	for suite_path: String in SUITES:
		var suite_script: GDScript = load(suite_path)
		if suite_script == null:
			failed += 1
			failure_log.append("%s: could not be loaded" % suite_path)
			continue

		var suite_name: String = suite_path.get_file().get_basename()
		# A suite that contributes nothing is a broken suite, not a passing one:
		# load() hands back a script that failed to compile rather than null, so
		# without this a syntax error in a suite reads as a green run.
		var method_names: PackedStringArray = _test_methods(suite_script)
		if method_names.is_empty():
			failed += 1
			failure_log.append("%s: no test methods found (did it fail to compile?)" % suite_path)
			continue

		for method_name: String in method_names:
			var test: DevicePowerTestCase = suite_script.new()
			errors.reset()
			test.before_each()
			test.call(method_name)
			test.after_each()
			var logged := errors.messages.size()
			if logged != test.expected_errors:
				test.fail(
					(
						"%d engine/script error(s) logged, %d expected: %s"
						% [logged, test.expected_errors, " | ".join(errors.messages)]
					)
				)

			if test.failures.is_empty():
				passed += 1
				print("  ok   %s.%s" % [suite_name, method_name])
			else:
				failed += 1
				print("  FAIL %s.%s" % [suite_name, method_name])
				for failure: String in test.failures:
					failure_log.append("%s.%s: %s" % [suite_name, method_name, failure])
					print("       %s" % failure)

	OS.remove_logger(errors)
	print("")
	if failed > 0:
		print("Failures:")
		for entry: String in failure_log:
			print("  - %s" % entry)
		print("")
	print("%d passed, %d failed, %d total" % [passed, failed, passed + failed])

	quit(1 if failed > 0 else 0)


func _test_methods(suite_script: GDScript) -> PackedStringArray:
	var names: PackedStringArray = []
	for method: Dictionary in suite_script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	return names


## Records every error and script error the engine logs. Warnings are not
## counted: the addon warns on purpose (a missing AAR, an old plugin).
class ErrorCounter:
	extends Logger

	var messages: PackedStringArray = []

	func reset() -> void:
		messages.clear()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		messages.append("%s (%s:%d %s)" % [text, file.get_file(), line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass
