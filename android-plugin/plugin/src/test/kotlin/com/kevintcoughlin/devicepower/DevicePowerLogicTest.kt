// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

package com.kevintcoughlin.devicepower

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PowerSourceTest {
    @Test
    fun pluggedZeroIsBattery() = assertEquals(PowerSource.BATTERY, PowerSource.fromPlugged(0))

    @Test
    fun anyPlugBitIsExternal() {
        // BATTERY_PLUGGED_AC 1, USB 2, WIRELESS 4, DOCK 8, and combinations.
        for (plugged in listOf(1, 2, 4, 8, 3)) {
            assertEquals("plugged=$plugged", PowerSource.EXTERNAL, PowerSource.fromPlugged(plugged))
        }
    }

    @Test
    fun missingExtraIsUnknown() {
        assertEquals(PowerSource.UNKNOWN, PowerSource.fromPlugged(-1))
        assertEquals(PowerSource.UNKNOWN, PowerSource.fromPlugged(null))
    }
}

class TriStateTest {
    @Test
    fun mapsBooleansAndNull() {
        assertEquals(TriState.ON, TriState.of(true))
        assertEquals(TriState.OFF, TriState.of(false))
        assertEquals(TriState.UNKNOWN, TriState.of(null))
    }
}

class GameModesTest {
    @Test
    fun passesKnownModesOnApi31() {
        for (mode in 0..4) {
            assertEquals(mode, GameModes.normalize(mode, 31))
        }
    }

    @Test
    fun unsupportedBeforeApi31() = assertEquals(GameModes.UNSUPPORTED, GameModes.normalize(2, 30))

    @Test
    fun undocumentedModesAreUnsupported() {
        assertEquals(GameModes.UNSUPPORTED, GameModes.normalize(5, 36))
        assertEquals(GameModes.UNSUPPORTED, GameModes.normalize(-1, 36))
        assertEquals(GameModes.UNSUPPORTED, GameModes.normalize(null, 36))
    }
}

class ThermalStatusTest {
    @Test
    fun passesKnownStatusesOnApi29() {
        for (status in 0..6) {
            assertEquals(status, ThermalStatus.normalize(status, 29))
        }
    }

    @Test
    fun unknownBeforeApi29() = assertEquals(ThermalStatus.UNKNOWN, ThermalStatus.normalize(0, 28))

    @Test
    fun undocumentedStatusesAreUnknown() {
        assertEquals(ThermalStatus.UNKNOWN, ThermalStatus.normalize(7, 36))
        assertEquals(ThermalStatus.UNKNOWN, ThermalStatus.normalize(-2, 36))
        assertEquals(ThermalStatus.UNKNOWN, ThermalStatus.normalize(null, 36))
    }
}

class RefreshRatesTest {
    private fun mode(w: Int, h: Int, rate: Float, vararg alternatives: Float) =
        DisplayModeSpec(w, h, rate, alternatives.toList())

    @Test
    fun pixelStyleModesAtTheCurrentResolution() {
        val current = mode(1080, 2424, 120.00001f)
        val modes = listOf(
            mode(1080, 2424, 60.000004f),
            current,
            mode(1344, 2992, 60f),
            mode(1344, 2992, 120f),
        )
        assertArrayEquals(
            floatArrayOf(60.000004f, 120.00001f),
            RefreshRates.atResolution(current, modes),
            0f,
        )
    }

    @Test
    fun alternativeRatesAreIncluded() {
        val current = mode(1080, 2340, 90f, 60f, 45f)
        assertArrayEquals(
            floatArrayOf(45f, 60f, 90f),
            RefreshRates.atResolution(current, listOf(current)),
            0f,
        )
    }

    @Test
    fun aFixedPanelIsOneRate() {
        // Galaxy A16 and Lenovo TB336FU, as apps see them.
        val current = mode(1080, 2340, 90f)
        assertArrayEquals(floatArrayOf(90f), RefreshRates.atResolution(current, listOf(current)), 0f)
    }

    @Test
    fun theCurrentModeCountsEvenIfUnlisted() {
        val current = mode(800, 1280, 90f)
        assertArrayEquals(floatArrayOf(90f), RefreshRates.atResolution(current, emptyList()), 0f)
    }

    @Test
    fun duplicatesAndGarbageAreDropped() {
        val current = mode(100, 100, 60f, 60f, Float.NaN, -1f, 0f, Float.POSITIVE_INFINITY)
        val modes = listOf(current, mode(100, 100, 60.001f), mode(100, 100, 59.94f))
        assertArrayEquals(floatArrayOf(60f), RefreshRates.atResolution(current, modes), 0f)
    }

    @Test
    fun pixel10AlternativesDoNotDuplicateOtherModes() {
        // As a Pixel 10 reports them: each mode lists the other as an
        // alternative, with float noise. Seen as [60, 120, 120] on device.
        val sixty = mode(1080, 2424, 60.0000038f, 120.0000076f)
        val oneTwenty = mode(1080, 2424, 120.0000076f, 60.0000038f)
        assertArrayEquals(
            floatArrayOf(60.0000038f, 120.0000076f),
            RefreshRates.atResolution(sixty, listOf(sixty, oneTwenty)),
            0f,
        )
    }

    @Test
    fun ratesWithinHalfAHertzAreOne() {
        val current = mode(1, 1, 90f, 89.7f, 90.4f, 89.4f)
        assertArrayEquals(floatArrayOf(89.4f, 90f), RefreshRates.atResolution(current, emptyList()), 0f)
    }

    @Test
    fun noCurrentModeIsUnknown() =
        assertEquals(0, RefreshRates.atResolution(null, listOf(mode(1, 1, 60f))).size)
}

class FrameRateVoteTest {
    @Test
    fun acceptsRatesAndWithdrawal() {
        assertEquals(120f, FrameRateVote.sanitize(120f))
        assertEquals(30f, FrameRateVote.sanitize(30f))
        assertEquals(0f, FrameRateVote.sanitize(0f))
    }

    @Test
    fun refusesGarbage() {
        for (rate in listOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, -1f, 1000.5f)) {
            assertNull("rate=$rate", FrameRateVote.sanitize(rate))
        }
    }
}

class PowerSnapshotTest {
    @Test
    fun diffsAreGroupedBySignal() {
        val base = PowerSnapshot()
        assertTrue(base.copy(powerSource = PowerSource.BATTERY).powerDiffers(base))
        assertTrue(base.copy(powerSaver = TriState.ON).powerDiffers(base))
        assertFalse(base.copy(gameMode = 2).powerDiffers(base))
        assertTrue(base.copy(gameMode = 2).gameModeDiffers(base))
        assertTrue(base.copy(thermalStatus = 3).thermalDiffers(base))
        assertTrue(base.copy(refreshRates = listOf(60f)).refreshRatesDiffer(base))
        assertFalse(base.copy().refreshRatesDiffer(base))
    }
}
