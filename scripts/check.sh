#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Formatting, static analysis and the test suites, as CI runs them.
#
#   scripts/check.sh format    Rewrite GDScript in place (gdformat).
#   scripts/check.sh lint      gdformat --check, gdlint, bash -n, the
#                              shell linter and reuse lint.
#   scripts/check.sh check     Lint, the GDScript suite, the editor-load
#                              smoke test, then the Gradle build (AARs, JVM
#                              unit tests, Android lint). Everything CI does.
#
# Single steps, as the CI jobs call them: gdscript, shell, reuse, tests,
# editor, android.
#
# Every Python tool is run through uvx at a pinned version, so local results
# match CI exactly; only uv (https://docs.astral.sh/uv/), Godot 4.7 and, for
# the Gradle build, JDK 21 plus the Android SDK are required.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GDTOOLKIT_VERSION="4.5.0"
SHELLCHECK_VERSION="0.11.0.1"
REUSE_VERSION="6.2.0"

GDSCRIPT_DIRS=(addons tests demo)
SHELL_FILES=(scripts/*.sh)

uvx_tool() {
	local package="$1"
	shift
	uvx --quiet --from "$package" "$@"
}

gdformat() { uvx_tool "gdtoolkit==$GDTOOLKIT_VERSION" gdformat "$@"; }
gdlint() { uvx_tool "gdtoolkit==$GDTOOLKIT_VERSION" gdlint "$@"; }
shellcheck() { uvx_tool "shellcheck-py==$SHELLCHECK_VERSION" shellcheck "$@"; }
reuse() { uvx_tool "reuse==$REUSE_VERSION" reuse "$@"; }

step() {
	echo
	echo "==> $*"
}

godot_bin() {
	local candidate
	for candidate in "${GODOT:-}" godot godot4 Godot; do
		if [[ -n "$candidate" ]] && command -v "$candidate" >/dev/null 2>&1; then
			echo "$candidate"
			return 0
		fi
	done
	echo "No Godot binary found. Set GODOT=/path/to/godot (4.7 or newer)." >&2
	return 2
}

run_format() {
	step "gdformat (rewrite)"
	gdformat "${GDSCRIPT_DIRS[@]}"
}

lint_gdscript() {
	step "gdformat --check / gdlint $GDTOOLKIT_VERSION"
	gdformat --check "${GDSCRIPT_DIRS[@]}"
	gdlint "${GDSCRIPT_DIRS[@]}"
}

lint_shell() {
	step "bash -n / shellcheck $SHELLCHECK_VERSION"
	local script
	for script in "${SHELL_FILES[@]}"; do
		bash -n "$script"
	done
	shellcheck "${SHELL_FILES[@]}"
}

lint_reuse() {
	step "reuse lint $REUSE_VERSION"
	reuse lint
}

run_lint() {
	lint_gdscript
	lint_shell
	lint_reuse
}

run_tests() {
	step "GDScript test suite"
	./scripts/run_tests.sh
}

# Starts the editor headlessly with the plugin enabled, which loads plugin.gd
# and the export plugin it registers, and fails on any error it logs. An
# EditorExportPlugin cannot be instantiated outside the editor, so this is the
# only automatic check that the editor side loads at all.
run_editor_smoke() {
	step "editor load smoke test"
	local godot log before
	godot="$(godot_bin)"
	log="$(mktemp)"
	before="$(mktemp)"
	cp "$REPO_ROOT/project.godot" "$before"
	"$godot" --headless --editor --verbose --path "$REPO_ROOT" --quit-after 120 >"$log" 2>&1 || true
	# Opening and closing the editor must not touch project.godot. This
	# catches a rewrite on editor start; the export path (where an autoload
	# added in _enter_tree and removed in _exit_tree did rewrite a game's
	# project.godot) needs an export to check, which this smoke test skips.
	if ! cmp -s "$before" "$REPO_ROOT/project.godot"; then
		diff -u "$before" "$REPO_ROOT/project.godot" >&2 || true
		cp "$before" "$REPO_ROOT/project.godot"
		rm -f "$before"
		echo "Starting the editor rewrote project.godot (restored)." >&2
		return 1
	fi
	rm -f "$before"
	if grep -E "^(SCRIPT )?ERROR|Parse Error" "$log"; then
		echo "The editor logged errors while loading the plugin (log: $log)." >&2
		return 1
	fi
	if ! grep -q "Completed load for: 'res://addons/device_power/plugin.gd'" "$log"; then
		echo "The editor did not load res://addons/device_power/plugin.gd (log: $log)." >&2
		return 1
	fi
	rm -f "$log"
	echo "plugin.gd and export_plugin.gd loaded without errors"
}

run_android() {
	step "Gradle build: AARs, JVM unit tests, Android lint"
	./scripts/build_android.sh build
}

run_check() {
	run_lint
	run_tests
	run_editor_smoke
	run_android
}

usage() {
	sed -n '5,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
	format) run_format ;;
	lint) run_lint ;;
	check) run_check ;;
	gdscript) lint_gdscript ;;
	shell) lint_shell ;;
	reuse) lint_reuse ;;
	tests) run_tests ;;
	editor) run_editor_smoke ;;
	android) run_android ;;
	-h | --help | help) usage ;;
	*)
		usage >&2
		exit 2
		;;
esac
