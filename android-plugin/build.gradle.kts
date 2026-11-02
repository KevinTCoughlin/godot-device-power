// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

// AGP, Kotlin and Gradle match what Godot 4.7.2's Android build template
// uses (platform/android/java/app/config.gradle), so the AAR is compiled by
// the same toolchain that links it into a game, and its Kotlin metadata is
// readable by the template's Kotlin 2.1 compiler.
//
// Godot 4.8 beta 2's template keeps that Kotlin (2.1.21), Java 17, minSdk 24,
// compile/target SDK 36 and NDK r29, and raises AGP from 8.6.1 to 8.13.2.
// This library stays on 8.6.1 so a build for the stable template is unchanged.
// scripts/check_godot_lib.sh compiles the same sources against the beta's
// godot-lib AAR without moving the pin.
plugins {
    id("com.android.library") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.21" apply false
}
