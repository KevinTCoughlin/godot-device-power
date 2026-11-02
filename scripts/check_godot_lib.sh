#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Compiles the Android plugin against the godot-lib AAR shipped with Godot
# 4.8 beta 2. That AAR is on the engine's GitHub release, not Maven Central
# (newest there is 4.7.2.stable). The default build pin stays 4.7.2.stable;
# this does not change what a release archive ships.
#
# The download is checked against the SHA-512 pinned below, which is the
# digest in that release's SHA512-SUMS.txt (published 2026-10-29). The sums
# file is downloaded too, and the pin has to match it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TAG="4.8-beta2"
AAR_NAME="godot-lib.4.8.beta2.template_release.aar"
# SHA512-SUMS.txt on the 4.8-beta2 release.
EXPECTED_SHA512="06ff74be3aec1f4c3f6c9a7bfa19153552efc5cdd8e79372e92b4cb0f0140ffe6ae8b1daf47570892d3361be4fdc6187a7913044c0631b027017ff97947f0646"
BASE="https://github.com/godotengine/godot-builds/releases/download/${TAG}"

dest="${REPO_ROOT}/build/godot-lib"
mkdir -p "$dest"

curl -fsSL --retry 5 --retry-delay 2 -o "${dest}/SHA512-SUMS.txt" "${BASE}/SHA512-SUMS.txt"
if ! grep -qx "${EXPECTED_SHA512}  ${AAR_NAME}" "${dest}/SHA512-SUMS.txt"; then
	echo "SHA512-SUMS.txt for ${TAG} does not list the pinned digest of ${AAR_NAME}." >&2
	exit 1
fi

if [[ ! -f "${dest}/${AAR_NAME}" ]] || ! (cd "$dest" && printf '%s  %s\n' "$EXPECTED_SHA512" "$AAR_NAME" | sha512sum -c --status -); then
	echo "Downloading ${AAR_NAME}"
	curl -fL --retry 5 --retry-delay 2 -o "${dest}/${AAR_NAME}" "${BASE}/${AAR_NAME}"
fi

(cd "$dest" && printf '%s  %s\n' "$EXPECTED_SHA512" "$AAR_NAME" | sha512sum -c -)

GODOT_LIB_AAR="${dest}/${AAR_NAME}" "${REPO_ROOT}/scripts/build_android.sh" build
