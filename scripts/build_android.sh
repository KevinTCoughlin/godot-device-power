#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kevin Coughlin
#
# SPDX-License-Identifier: MIT
#
# Builds the DevicePowerAndroid plugin and runs its unit tests and Android
# lint: `gradlew build`. The debug and release AARs are copied into
# addons/device_power/bin/, where the export plugin finds them.
#
#   scripts/build_android.sh            build, unit tests, lint
#   scripts/build_android.sh assemble   AARs only
#
# Needs JDK 21 (JAVA_HOME, or java on PATH) and an Android SDK with platform
# 36 (ANDROID_HOME, or sdk.dir in android-plugin/local.properties).
#
# GODOT_LIB_AAR, when set, compiles against that godot-lib file instead of
# org.godotengine:godot:4.7.2.stable. The release pin does not change.
# scripts/check_godot_lib.sh sets it for the 4.8 beta 2 AAR.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/android-plugin"

case "${1:-build}" in
	build) tasks=(build) ;;
	assemble) tasks=(assembleDebug assembleRelease) ;;
	*)
		echo "usage: $0 [build|assemble]" >&2
		exit 2
		;;
esac

gradle_args=()
if [[ -n "${GODOT_LIB_AAR:-}" ]]; then
	if [[ ! -f "$GODOT_LIB_AAR" ]]; then
		echo "GODOT_LIB_AAR is not a file: $GODOT_LIB_AAR" >&2
		exit 2
	fi
	gradle_args+=("-PgodotLibAar=$GODOT_LIB_AAR")
	echo "Compiling against $GODOT_LIB_AAR"
fi

./gradlew --no-daemon --console=plain "${gradle_args[@]}" "${tasks[@]}"

for aar in debug/device_power-debug.aar release/device_power-release.aar; do
	test -f "$REPO_ROOT/addons/device_power/bin/$aar"
	echo "built addons/device_power/bin/$aar"
done
