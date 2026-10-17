# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
class_name DevicePowerTestCase
extends RefCounted

## Minimal assertion base class for the suite.
##
## Every test builds a facade, injects a [DevicePowerMockBackend] (or a
## backend over a fake plugin), and asserts on what it reports, what it
## voted and which signals it emitted. Time is a fake clock the test moves.

const FACADE_SCRIPT := preload("res://addons/device_power/device_power.gd")

var failures: PackedStringArray = []
## Engine or script errors this test expects to be logged.
var expected_errors: int = 0

var power: Node = null
var mock: DevicePowerMockBackend = null
## How many times [signal DevicePower.changed] fired.
var changes: int = 0
## The fake clock, in seconds.
var now: float = 0.0

var _saved_max_fps: int = 0


## Runs before every test method.
func before_each() -> void:
	_saved_max_fps = Engine.max_fps
	Engine.max_fps = 0
	mock = DevicePowerMockBackend.new()
	power = make_facade()
	power.set_backend(mock)


## Runs after every test method.
func after_each() -> void:
	if power != null:
		power.free()
		power = null
	mock = null
	Engine.max_fps = _saved_max_fps


## A facade with the fake clock and the change counter attached, no backend.
func make_facade() -> Node:
	var facade: Node = FACADE_SCRIPT.new()
	facade._clock = func() -> float: return now
	facade.changed.connect(func() -> void: changes += 1)
	return facade


## Declares that [param count] errors will be logged during this test.
func expect_errors(count: int) -> void:
	expected_errors = count


func fail(message: String) -> void:
	failures.append(message)


func assert_true(value: bool, message: String = "") -> void:
	if not value:
		fail("expected true; %s" % _describe(message))


func assert_false(value: bool, message: String = "") -> void:
	if value:
		fail("expected false; %s" % _describe(message))


## Equal in value and in type: 1 and 1.0, or 1 and true, are not equal.
func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("expected %s, got %s; %s" % [_repr(expected), _repr(actual), _describe(message)])


func assert_null(value: Variant, message: String = "") -> void:
	if value != null:
		fail("expected null, got %s; %s" % [_repr(value), _describe(message)])


func _repr(value: Variant) -> String:
	if value == null:
		return "<null>"
	return "%s(%s)" % [type_string(typeof(value)), value]


func _describe(message: String) -> String:
	return message if not message.is_empty() else "no detail"
