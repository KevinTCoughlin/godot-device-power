// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "godot-device-power"
include(":plugin")
