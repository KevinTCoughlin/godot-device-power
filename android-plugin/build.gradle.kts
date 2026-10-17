// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

// AGP, Kotlin and Gradle match what Godot 4.7.2's Android build template
// uses (platform/android/java/app/config.gradle), so the AAR is compiled by
// the same toolchain that links it into a game, and its Kotlin metadata is
// readable by the template's Kotlin 2.1 compiler.
plugins {
    id("com.android.library") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.21" apply false
}
