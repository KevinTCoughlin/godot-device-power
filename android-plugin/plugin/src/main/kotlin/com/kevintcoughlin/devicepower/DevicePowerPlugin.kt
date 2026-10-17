// SPDX-FileCopyrightText: 2026 Kevin Coughlin
//
// SPDX-License-Identifier: MIT

package com.kevintcoughlin.devicepower

import android.app.Activity
import android.app.GameManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.View
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * The `DevicePowerAndroid` engine singleton: power source, battery saver,
 * game mode, thermal status and refresh rates, pushed to Godot as signals,
 * and a frame rate vote on Godot's render surface.
 *
 * Threads. Three are involved, and each member says which it runs on:
 * - the main (UI) thread: lifecycle callbacks, the broadcast receiver, the
 *   thermal listener and the SurfaceHolder callback. All registration and
 *   every platform read happen here.
 * - Godot's thread (the render thread): every @UsedByGodot method. Getters
 *   only read [snapshot], a @Volatile immutable value, so a game never waits
 *   on a binder call. [voteFrameRate] calls Surface.setFrameRate() directly,
 *   under [voteLock], so it can say whether the vote was made.
 * - Signals are queued to Godot's thread by [emitSignal].
 *
 * Every platform call is wrapped: a failure reads as "unknown", never as a
 * guess and never as an exception into the engine.
 */
class DevicePowerPlugin(godot: Godot) : GodotPlugin(godot) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val sdkInt = Build.VERSION.SDK_INT

    /** The last read. Written on the main thread, read on any. */
    @Volatile
    private var snapshot = PowerSnapshot()

    // Main thread only.
    private var receiverRegistered = false
    private var thermalListener: Any? = null
    private var surfaceHolder: SurfaceHolder? = null

    private val voteLock = Any()

    /** The last rate Godot asked for, re-applied to a new surface. Under [voteLock]. */
    private var requestedRate: Float? = null

    /** Battery level/plug changes and battery saver toggles. Main thread. */
    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            update(read(stickyBattery = intent.takeIf { it.action == Intent.ACTION_BATTERY_CHANGED }))
        }
    }

    /** Keeps the vote on a recreated surface. Main thread. */
    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            reapplyVote()
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            reapplyVote()
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
    }

    override fun getPluginName(): String = NAME

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIGNAL_POWER, Int::class.javaObjectType, Int::class.javaObjectType),
        SignalInfo(SIGNAL_GAME_MODE, Int::class.javaObjectType),
        SignalInfo(SIGNAL_THERMAL, Int::class.javaObjectType),
        SignalInfo(SIGNAL_REFRESH_RATES),
    )

    // Lifecycle: main thread.

    override fun onMainCreate(activity: Activity?): View? {
        // A first read before the engine starts, so the first getter call has
        // an answer. Nothing is emitted: nobody is connected yet.
        snapshot = read(stickyBattery = null)
        return null
    }

    override fun onGodotSetupCompleted() {
        // The render view exists from here on.
        mainHandler.post { attachSurfaceCallback() }
    }

    override fun onMainResume() {
        start()
    }

    override fun onMainPause() {
        stop()
    }

    override fun onMainDestroy() {
        stop()
        surfaceHolder?.removeCallback(surfaceCallback)
        surfaceHolder = null
    }

    // Called from Godot: Godot's thread.

    /** Lets the GDScript backend refuse a plugin it was not written for. */
    @UsedByGodot
    fun getApiVersion(): Int = API_VERSION

    @UsedByGodot
    fun getSdkInt(): Int = sdkInt

    /** DevicePower.PowerSource: -1 unknown, 0 battery, 1 external. */
    @UsedByGodot
    fun getPowerSource(): Int = snapshot.powerSource

    /** Battery saver: -1 unknown, 0 off, 1 on. */
    @UsedByGodot
    fun getPowerSaver(): Int = snapshot.powerSaver

    /** DevicePower.GameMode, Android's numbering; 0 before API 31. */
    @UsedByGodot
    fun getGameMode(): Int = snapshot.gameMode

    /** DevicePower.ThermalStatus, PowerManager's numbering; -1 before API 29. */
    @UsedByGodot
    fun getThermalStatus(): Int = snapshot.thermalStatus

    /** Refresh rates at the current resolution, ascending; empty if unknown. */
    @UsedByGodot
    fun getRefreshRates(): FloatArray = snapshot.refreshRates.toFloatArray()

    /**
     * Re-reads everything on the main thread and emits what changed. The
     * game mode only changes through the Game Dashboard, which takes focus,
     * so the facade calls this on focus and resume.
     */
    @UsedByGodot
    fun refresh() {
        mainHandler.post { update(read(stickyBattery = null)) }
    }

    /**
     * Asks for [rate] frames per second on Godot's render surface with
     * Surface.setFrameRate(rate, FRAME_RATE_COMPATIBILITY_DEFAULT,
     * CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS); 0 withdraws the vote. Returns
     * whether the request was made now: false before API 31, without a valid
     * surface, or for a rate [FrameRateVote.sanitize] refuses. The rate is
     * kept and re-applied when the surface is created or changed, so a
     * refused vote for want of a surface is made as soon as there is one.
     */
    @UsedByGodot
    fun voteFrameRate(rate: Float): Boolean {
        val sane = FrameRateVote.sanitize(rate) ?: return false
        val made = synchronized(voteLock) {
            requestedRate = sane
            applyVoteLocked()
        }
        if (surfaceHolder == null) {
            mainHandler.post { attachSurfaceCallback() }
        }
        return made
    }

    // Main thread.

    private fun start() {
        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            }
            try {
                // Both are protected system broadcasts, which reach a
                // not-exported receiver; the flag is mandatory from API 34.
                if (Build.VERSION.SDK_INT >= 33) {
                    activityContext().registerReceiver(powerReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    activityContext().registerReceiver(powerReceiver, filter)
                }
                receiverRegistered = true
            } catch (e: RuntimeException) {
                Log.w(TAG, "Could not register the power receiver", e)
            }
        }
        if (Build.VERSION.SDK_INT >= 29 && thermalListener == null) {
            val power = powerManager()
            if (power != null) {
                val listener = PowerManager.OnThermalStatusChangedListener { status ->
                    update(snapshot.copy(thermalStatus = ThermalStatus.normalize(status, sdkInt)))
                }
                try {
                    power.addThermalStatusListener(activityContext().mainExecutor, listener)
                    thermalListener = listener
                } catch (e: RuntimeException) {
                    Log.w(TAG, "Could not add the thermal listener", e)
                }
            }
        }
        attachSurfaceCallback()
        update(read(stickyBattery = null))
        reapplyVote()
    }

    private fun stop() {
        if (receiverRegistered) {
            try {
                activityContext().unregisterReceiver(powerReceiver)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "The power receiver was not registered", e)
            }
            receiverRegistered = false
        }
        val listener = thermalListener
        if (Build.VERSION.SDK_INT >= 29 && listener is PowerManager.OnThermalStatusChangedListener) {
            try {
                powerManager()?.removeThermalStatusListener(listener)
            } catch (e: RuntimeException) {
                Log.w(TAG, "Could not remove the thermal listener", e)
            }
        }
        thermalListener = null
    }

    /** Publishes [next] and emits a signal for each part that changed. */
    private fun update(next: PowerSnapshot) {
        val previous = snapshot
        snapshot = next
        if (next.powerDiffers(previous)) {
            emitSignal(SIGNAL_POWER, next.powerSource, next.powerSaver)
        }
        if (next.gameModeDiffers(previous)) {
            emitSignal(SIGNAL_GAME_MODE, next.gameMode)
        }
        if (next.thermalDiffers(previous)) {
            emitSignal(SIGNAL_THERMAL, next.thermalStatus)
        }
        if (next.refreshRatesDiffer(previous)) {
            emitSignal(SIGNAL_REFRESH_RATES)
        }
    }

    /**
     * Reads everything. [stickyBattery] is an ACTION_BATTERY_CHANGED intent
     * already in hand; without one the sticky broadcast is fetched with a
     * null receiver, which registers nothing.
     */
    private fun read(stickyBattery: Intent?): PowerSnapshot {
        val context = activityContext()
        val battery = stickyBattery ?: guarded("battery") {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val power = powerManager()
        val saver = guarded("battery saver") { power?.isPowerSaveMode }
        val gameMode = if (Build.VERSION.SDK_INT >= 31) {
            guarded("game mode") { context.getSystemService(GameManager::class.java)?.gameMode }
        } else {
            null
        }
        val thermal = if (Build.VERSION.SDK_INT >= 29) guarded("thermal status") { power?.currentThermalStatus } else null
        return PowerSnapshot(
            powerSource = PowerSource.fromPlugged(plugged),
            powerSaver = TriState.of(saver),
            gameMode = GameModes.normalize(gameMode, sdkInt),
            thermalStatus = ThermalStatus.normalize(thermal, sdkInt),
            refreshRates = (guarded("refresh rates") { readRefreshRates() } ?: FloatArray(0)).toList(),
        )
    }

    private fun readRefreshRates(): FloatArray {
        val display = display() ?: return FloatArray(0)
        fun spec(mode: Display.Mode) = DisplayModeSpec(
            width = mode.physicalWidth,
            height = mode.physicalHeight,
            refreshRate = mode.refreshRate,
            alternativeRates = if (Build.VERSION.SDK_INT >= 31) mode.alternativeRefreshRates.toList() else emptyList(),
        )
        return RefreshRates.atResolution(spec(display.mode), display.supportedModes.map(::spec))
    }

    private fun display(): Display? {
        val activity = activity ?: return null
        return if (Build.VERSION.SDK_INT >= 30) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
    }

    private fun attachSurfaceCallback() {
        val holder = guarded("render surface") { godot.renderView?.view?.holder } ?: return
        if (holder === surfaceHolder) {
            return
        }
        surfaceHolder?.removeCallback(surfaceCallback)
        holder.addCallback(surfaceCallback)
        surfaceHolder = holder
    }

    private fun reapplyVote() {
        synchronized(voteLock) { applyVoteLocked() }
    }

    // Any thread, under voteLock.

    private fun applyVoteLocked(): Boolean {
        val rate = requestedRate ?: return false
        if (Build.VERSION.SDK_INT < 31) {
            return false
        }
        val surface: Surface = guarded("render surface") { godot.renderView?.view?.holder?.surface }
            ?: return false
        if (!surface.isValid) {
            return false
        }
        return try {
            surface.setFrameRate(
                rate,
                Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
            )
            true
        } catch (e: RuntimeException) {
            // IllegalArgumentException for a rate the platform refuses;
            // IllegalStateException if the surface went away in between.
            Log.w(TAG, "Surface.setFrameRate($rate) failed", e)
            false
        }
    }

    private fun activityContext(): Context = activity ?: context

    private fun powerManager(): PowerManager? =
        guarded("power manager") { activityContext().getSystemService(PowerManager::class.java) }

    /** Runs [block], logging and swallowing any platform failure as null. */
    private inline fun <T> guarded(what: String, block: () -> T?): T? = try {
        block()
    } catch (e: RuntimeException) {
        Log.w(TAG, "Reading $what failed", e)
        null
    }

    companion object {
        /** The engine singleton's name, Engine.get_singleton("DevicePowerAndroid"). */
        const val NAME = "DevicePowerAndroid"

        /** Bumped when a method or signal changes meaning or shape. */
        const val API_VERSION = 1

        const val SIGNAL_POWER = "power_changed"
        const val SIGNAL_GAME_MODE = "game_mode_changed"
        const val SIGNAL_THERMAL = "thermal_status_changed"
        const val SIGNAL_REFRESH_RATES = "refresh_rates_changed"

        private const val TAG = "DevicePower"
    }
}
