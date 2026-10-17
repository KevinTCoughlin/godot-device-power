// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

package com.kevintcoughlin.devicepower

// Everything here is plain Kotlin with no android.* types, so it runs in JVM
// unit tests. DevicePowerPlugin reads the platform and hands the raw values
// to these functions; what Godot sees is decided here.
//
// The numbers are the GDScript facade's: PowerSource, GameMode and
// ThermalStatus in addons/device_power/device_power.gd. "Unknown" is always
// an explicit value, never a guess.

/** Where the power comes from: DevicePower.PowerSource. */
object PowerSource {
    const val UNKNOWN = -1
    const val BATTERY = 0
    const val EXTERNAL = 1

    /**
     * The sticky ACTION_BATTERY_CHANGED intent's `plugged` extra: 0 on the
     * battery, a bit set (AC, USB, wireless, dock) on external power, and
     * -1 here when the extra or the intent is missing.
     *
     * `plugged`, not BatteryManager.isCharging(): a full or charge-limited
     * battery on a charger is not charging, but it is on external power.
     */
    fun fromPlugged(plugged: Int?): Int = when {
        plugged == null || plugged < 0 -> UNKNOWN
        plugged == 0 -> BATTERY
        else -> EXTERNAL
    }
}

/** A boolean that can be unknown, as an Int Godot cannot misread. */
object TriState {
    const val UNKNOWN = -1
    const val OFF = 0
    const val ON = 1

    fun of(value: Boolean?): Int = when (value) {
        null -> UNKNOWN
        true -> ON
        false -> OFF
    }
}

/** android.app.GameManager modes: DevicePower.GameMode. */
object GameModes {
    const val UNSUPPORTED = 0
    const val CUSTOM = 4

    /** GameManager arrived in API 31; anything outside 0..4 is unsupported. */
    fun normalize(mode: Int?, sdkInt: Int): Int = when {
        sdkInt < 31 || mode == null -> UNSUPPORTED
        mode in UNSUPPORTED..CUSTOM -> mode
        else -> UNSUPPORTED
    }
}

/** PowerManager.THERMAL_STATUS_*: DevicePower.ThermalStatus. */
object ThermalStatus {
    const val UNKNOWN = -1
    const val NONE = 0
    const val SHUTDOWN = 6

    /** Thermal status arrived in API 29; anything outside 0..6 is unknown. */
    fun normalize(status: Int?, sdkInt: Int): Int = when {
        sdkInt < 29 || status == null -> UNKNOWN
        status in NONE..SHUTDOWN -> status
        else -> UNKNOWN
    }
}

/** One Display.Mode, reduced to what the refresh rate list needs. */
data class DisplayModeSpec(
    val width: Int,
    val height: Int,
    val refreshRate: Float,
    /** Display.Mode.getAlternativeRefreshRates() (API 31+), else empty. */
    val alternativeRates: List<Float> = emptyList(),
)

object RefreshRates {
    /**
     * Rates within this many Hz are one rate: display rates carry float
     * noise (60.0000038, 120.0000076), and one rate can be listed by several
     * modes and their alternatives. Matches DevicePowerBackend.SAME_RATE_HZ.
     */
    const val SAME_RATE_HZ = 0.5f

    /**
     * The rates the display can run at its current resolution, ascending:
     * every supported mode of that size, plus each one's alternative rates,
     * each rate once (within [SAME_RATE_HZ]; the first seen is kept).
     * Non-finite and non-positive rates are dropped. Empty when the current
     * mode is unknown.
     *
     * Apps can only see what the platform reports: a Galaxy A16 lists 60 as
     * an alternative of its single 90 Hz mode in dumpsys, but apps get [90].
     */
    fun atResolution(current: DisplayModeSpec?, modes: List<DisplayModeSpec>): FloatArray {
        if (current == null) {
            return FloatArray(0)
        }
        val rates = mutableListOf<Float>()
        fun add(rate: Float) {
            if (rate.isFinite() && rate > 0f && rates.none { kotlin.math.abs(it - rate) < SAME_RATE_HZ }) {
                rates.add(rate)
            }
        }
        // The current mode is always one the display can run, even if a
        // vendor leaves it out of getSupportedModes().
        for (mode in listOf(current) + modes) {
            if (mode.width != current.width || mode.height != current.height) {
                continue
            }
            add(mode.refreshRate)
            mode.alternativeRates.forEach(::add)
        }
        return rates.sorted().toFloatArray()
    }
}

object FrameRateVote {
    /** Above any panel's rate; a larger request is a bug in the caller. */
    const val MAX_RATE = 1000f

    /**
     * The rate to pass to Surface.setFrameRate(), or null to refuse the
     * request. 0 withdraws a vote; NaN, infinities, negatives and absurd
     * rates are refused rather than clamped, so a caller bug is visible as
     * a failed vote instead of an unexpected refresh rate.
     */
    fun sanitize(rate: Float): Float? =
        if (rate.isFinite() && rate >= 0f && rate <= MAX_RATE) rate else null
}

/** Everything the plugin reports, as of its last read. */
data class PowerSnapshot(
    val powerSource: Int = PowerSource.UNKNOWN,
    val powerSaver: Int = TriState.UNKNOWN,
    val gameMode: Int = GameModes.UNSUPPORTED,
    val thermalStatus: Int = ThermalStatus.UNKNOWN,
    val refreshRates: List<Float> = emptyList(),
) {
    fun powerDiffers(other: PowerSnapshot) =
        powerSource != other.powerSource || powerSaver != other.powerSaver

    fun gameModeDiffers(other: PowerSnapshot) = gameMode != other.gameMode

    fun thermalDiffers(other: PowerSnapshot) = thermalStatus != other.thermalStatus

    fun refreshRatesDiffer(other: PowerSnapshot) = refreshRates != other.refreshRates
}
