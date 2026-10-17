#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Runs the mock-backed GDScript test suite headlessly.
#
# The suite never touches a device: Android is a fake singleton, so it gives
# the same results on a developer desktop and on a CI runner.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GODOT_BIN="${GODOT:-}"
if [[ -z "$GODOT_BIN" ]]; then
	for candidate in godot godot4 Godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			GODOT_BIN="$candidate"
			break
		fi
	done
fi

if [[ -z "$GODOT_BIN" ]]; then
	echo "No Godot binary found. Set GODOT=/path/to/godot (4.7 or newer)." >&2
	exit 2
fi

echo "Using Godot: $("$GODOT_BIN" --headless --version)"

# The first headless run imports assets and builds the global class cache the
# suite relies on. Godot 4.7 can crash while quitting after a project's first
# import (godotengine/godot#111048: a deferred doc generation that outlives
# the editor), with the import already written; so a failed import is retried
# once, and the retry's status is the one that counts.
if ! "$GODOT_BIN" --headless --path "$REPO_ROOT" --import >/dev/null 2>&1; then
	echo "warning: the first import failed (known Godot 4.7 crash on quit); retrying once" >&2
	"$GODOT_BIN" --headless --path "$REPO_ROOT" --import >/dev/null
fi

"$GODOT_BIN" --headless --path "$REPO_ROOT" --script res://tests/run_tests.gd
