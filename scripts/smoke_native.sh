#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Loads the installed GDExtension in Godot and checks the Linux build does
# not claim it can read the battery. Run after scripts/build_native.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

GODOT_BIN="${GODOT:-}"
if [[ -z "${GODOT_BIN}" ]]; then
	for candidate in godot godot4 Godot; do
		if command -v "${candidate}" >/dev/null 2>&1; then
			GODOT_BIN="${candidate}"
			break
		fi
	done
fi
if [[ -z "${GODOT_BIN}" ]]; then
	echo "No Godot binary found. Set GODOT=/path/to/godot (4.7 or newer)." >&2
	exit 2
fi

# The global class cache and the extension list are written by an import.
# A fresh tree has neither, so --script alone does not see the library.
# Godot 4.7 can crash while quitting after the first import; retry once.
if ! "${GODOT_BIN}" --headless --path "${REPO_ROOT}" --import >/dev/null 2>&1; then
	echo "warning: the first import failed (known Godot 4.7 crash on quit); retrying once" >&2
	"${GODOT_BIN}" --headless --path "${REPO_ROOT}" --import >/dev/null
fi

log="$(mktemp)"
set +e
"${GODOT_BIN}" --headless --path "${REPO_ROOT}" --script res://tests/smoke_native.gd >"${log}" 2>&1
status=$?
set -e
cat "${log}"
if [[ "${status}" -ne 0 ]]; then
	echo "native smoke exited ${status}" >&2
	exit "${status}"
fi
if grep -E "^(SCRIPT )?ERROR|Parse Error" "${log}"; then
	echo "native smoke logged an error" >&2
	exit 1
fi
rm -f "${log}"
