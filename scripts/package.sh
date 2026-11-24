#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Builds the install zip and the Godot Asset Library zip.
#
#   scripts/package.sh [expected-version]
#
# The debug and release AARs must already be in addons/device_power/bin/.
# This does not publish a release. CI uploads the zips as a build artifact;
# the release workflow is what attaches them to a draft release.
#
# The zip container is reproducible for a given tree and SOURCE_DATE_EPOCH:
# entries are sorted, timestamps are pinned, and extra zip fields are
# omitted. When SOURCE_DATE_EPOCH is unset it is the HEAD commit time.
# AAR bytes come from Gradle. Those archive tasks pin entry order and
# timestamps too, so two builds of the same commit produce the same zips
# when the toolchain matches.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

expected="${1:-}"

version="$(sed -n 's/^version="\(.*\)"$/\1/p' addons/device_power/plugin.cfg)"
if [[ -z "$version" ]]; then
	echo "addons/device_power/plugin.cfg has no version." >&2
	exit 1
fi
if [[ -n "$expected" && "$expected" != "$version" ]]; then
	echo "plugin.cfg says version=\"${version}\", not \"${expected}\"." >&2
	exit 1
fi

debug_aar="addons/device_power/bin/debug/device_power-debug.aar"
release_aar="addons/device_power/bin/release/device_power-release.aar"
if [[ ! -f "$debug_aar" || ! -f "$release_aar" ]]; then
	echo "Missing AARs. Run scripts/build_android.sh first." >&2
	exit 1
fi
for required in icon.png LICENSE plugin.cfg device_power.gd export_plugin.gd; do
	if [[ ! -f "addons/device_power/${required}" ]]; then
		echo "addons/device_power/${required} is missing." >&2
		exit 1
	fi
done

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
	SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
fi
export SOURCE_DATE_EPOCH
export TZ=UTC

name="godot-device-power-${version}"
rm -rf dist
mkdir -p "dist/${name}/addons" dist/store/addons

cp -a addons/device_power "dist/${name}/addons/"
cp README.md LICENSE CHANGELOG.md "dist/${name}/"
cp -a addons/device_power dist/store/addons/
cp README.md CHANGELOG.md dist/store/addons/device_power/
# The Asset Library archive keeps the addon folder, not dotfiles.
find dist/store -mindepth 1 -name '.*' -prune -exec rm -rf {} +

stamp() {
	find "$1" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
}
stamp "dist/${name}"
stamp dist/store

# Writes a zip of the given relative paths. Paths are stored sorted, with
# no extra fields, from workdir. The archive is written outside workdir
# first so it cannot be packed into itself.
write_zip() {
	local workdir="$1"
	local archive="$2"
	shift 2
	local list tmp
	list="$(mktemp)"
	tmp="$(mktemp)"
	rm -f "$tmp"
	(
		cd "$workdir"
		find "$@" -print | LC_ALL=C sort >"$list"
		zip -X -q "$tmp" -@ <"$list"
	)
	rm -f "$list"
	mv "$tmp" "$archive"
}

write_zip dist "dist/${name}.zip" "$name"
write_zip dist/store "dist/${name}-asset-store.zip" addons

(
	cd dist
	sha256sum "${name}.zip" >"${name}.zip.sha256"
	sha256sum "${name}-asset-store.zip" >"${name}-asset-store.zip.sha256"
)

require_member() {
	local archive="$1"
	local member="$2"
	if ! unzip -l "$archive" | grep -q " ${member}$"; then
		echo "${archive} is missing ${member}" >&2
		exit 1
	fi
}

release_zip="dist/${name}.zip"
store_zip="dist/${name}-asset-store.zip"
require_member "$release_zip" "${name}/addons/device_power/plugin.cfg"
require_member "$release_zip" "${name}/addons/device_power/icon.png"
require_member "$release_zip" "${name}/addons/device_power/LICENSE"
require_member "$release_zip" "${name}/addons/device_power/bin/debug/device_power-debug.aar"
require_member "$release_zip" "${name}/addons/device_power/bin/release/device_power-release.aar"
require_member "$release_zip" "${name}/README.md"
require_member "$release_zip" "${name}/LICENSE"
require_member "$release_zip" "${name}/CHANGELOG.md"
require_member "$store_zip" "addons/device_power/plugin.cfg"
require_member "$store_zip" "addons/device_power/icon.png"
require_member "$store_zip" "addons/device_power/LICENSE"
require_member "$store_zip" "addons/device_power/README.md"
require_member "$store_zip" "addons/device_power/CHANGELOG.md"
require_member "$store_zip" "addons/device_power/bin/debug/device_power-debug.aar"
require_member "$store_zip" "addons/device_power/bin/release/device_power-release.aar"
if unzip -l "$store_zip" | grep -q '/tests/'; then
	echo "The Asset Library zip contains tests." >&2
	exit 1
fi

unzip -l "$release_zip"
unzip -l "$store_zip"
echo "Packaged ${name} (SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH})"
