#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Compiles the Android plugin against the godot-lib AAR shipped with Godot
# 4.8 beta 5. That AAR is on the engine's GitHub release, not Maven Central
# (newest there is 4.7.2.stable). The default build pin stays 4.7.2.stable;
# this does not change what a release archive ships.
#
# The download is checked against the SHA-512 pinned below, which is the
# digest in that release's SHA512-SUMS.txt (published 2026-11-24). The sums
# file is downloaded too, and the pin has to match it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TAG="4.8-beta5"
AAR_NAME="godot-lib.4.8.beta5.template_release.aar"
# SHA512-SUMS.txt on the 4.8-beta5 release.
EXPECTED_SHA512="f6c05ccd5c887a9b25a0fa0be783304aaa03cc3a40c685380f10ba14b4ad74e52bad4a42ad0712b94aa15c9c1b0674fefd5aeef7e6f5e5bd99f135e3a866943a"
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
