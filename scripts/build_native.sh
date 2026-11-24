#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Builds the DevicePowerNative GDExtension and the host test of its power
# mapping.
#
#   scripts/build_native.sh
#
# Needs g++, scons, and the MinGW cross compiler x86_64-w64-mingw32-g++.
# godot-cpp is cloned into native/.godot-cpp unless GODOT_CPP points at a
# checkout. Libraries are installed into addons/device_power/bin/native/,
# which is gitignored. Single precision, api_version 4.7.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="${HOME}/.local/bin:${PATH}"

step() {
	echo
	echo "==> $*"
}

step "power-status mapping"
mapping_test="$(mktemp)"
g++ -std=c++17 -Wall -Wextra -Werror -I native/src \
	native/src/power_status.cpp native/tests/test_power_status.cpp \
	-o "${mapping_test}"
"${mapping_test}"
rm -f "${mapping_test}"

if ! command -v scons >/dev/null 2>&1; then
	echo "scons is required (https://scons.org)." >&2
	exit 1
fi
if ! command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
	echo "x86_64-w64-mingw32-g++ is required to cross-compile the Windows library." >&2
	exit 1
fi

GODOT_CPP="${GODOT_CPP:-${REPO_ROOT}/native/.godot-cpp}"
if [[ ! -f "${GODOT_CPP}/SConstruct" ]]; then
	step "clone godot-cpp"
	git clone --depth 1 https://github.com/godotengine/godot-cpp.git "${GODOT_CPP}"
fi
export GODOT_CPP

step "GDExtension (api 4.7, single precision)"
cd "${REPO_ROOT}/native"
jobs="$(nproc)"
for target in template_debug template_release; do
	scons platform=linux "target=${target}" arch=x86_64 api_version=4.7 "-j${jobs}"
	scons platform=windows "target=${target}" arch=x86_64 api_version=4.7 "-j${jobs}"
done

step "install into the addon"
dest="${REPO_ROOT}/addons/device_power/bin/native"
rm -rf "${dest}"
mkdir -p "${dest}"
shopt -s nullglob
libs=(bin/libdevice_power.*)
if [[ ${#libs[@]} -eq 0 ]]; then
	echo "no GDExtension libraries were built" >&2
	exit 1
fi
cp "${libs[@]}" "${dest}/"

gdextension="${dest}/device_power_native.gdextension"
{
	echo "[configuration]"
	echo "entry_symbol = \"device_power_library_init\""
	echo "compatibility_minimum = \"4.7\""
	echo
	echo "[libraries]"
	for lib in "${libs[@]}"; do
		base="$(basename "${lib}")"
		core="${base#libdevice_power.}"
		core="${core%.so}"
		core="${core%.dll}"
		platform="${core%%.*}"
		rest="${core#*.}"
		target="${rest%%.*}"
		arch="${rest#*.}"
		build="debug"
		if [[ "${target}" == "template_release" ]]; then
			build="release"
		fi
		printf '%s.%s.%s = "%s"\n' "${platform}" "${build}" "${arch}" "${base}"
	done
} >"${gdextension}"

echo "installed:"
find "${dest}" -type f -print
