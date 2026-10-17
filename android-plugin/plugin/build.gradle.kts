// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// Keep in step with addons/device_power/plugin.cfg and export_plugin.gd.
val pluginName = "device_power"
val godotVersion = "4.7.2.stable"

android {
    namespace = "com.kevintcoughlin.devicepower"
    compileSdk = 36

    defaultConfig {
        // Godot 4.7's own minimum; everything newer is gated at run time.
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    // Godot's template targets Java 17 bytecode; so does this library.
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = false
    }

    lint {
        abortOnError = true
        warningsAsErrors = true
        // Version-bump nags are Dependabot's job, and AGP/Kotlin follow
        // Godot's template on purpose (see ../build.gradle.kts).
        disable += setOf("GradleDependency", "AndroidGradlePluginVersion", "NewerVersionAvailable", "OldTargetApi")
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

dependencies {
    // Provided by the game's own Godot library at run time.
    compileOnly("org.godotengine:godot:$godotVersion")
    testImplementation("junit:junit:4.13.2")
}

// The export plugin (addons/device_power/export_plugin.gd) hands Godot these
// paths, relative to res://addons/.
val addonBin = rootProject.layout.projectDirectory.dir("../addons/$pluginName/bin")

val copyDebugAar by tasks.registering(Copy::class) {
    description = "Copies the debug AAR into the addon."
    from(layout.buildDirectory.file("outputs/aar/plugin-debug.aar"))
    into(addonBin.dir("debug"))
    rename { "$pluginName-debug.aar" }
}

val copyReleaseAar by tasks.registering(Copy::class) {
    description = "Copies the release AAR into the addon."
    from(layout.buildDirectory.file("outputs/aar/plugin-release.aar"))
    into(addonBin.dir("release"))
    rename { "$pluginName-release.aar" }
}

afterEvaluate {
    tasks.named("assembleDebug") { finalizedBy(copyDebugAar) }
    tasks.named("assembleRelease") { finalizedBy(copyReleaseAar) }
    copyDebugAar { dependsOn("assembleDebug") }
    copyReleaseAar { dependsOn("assembleRelease") }
}
