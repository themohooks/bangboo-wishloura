package com.example.fluttervpngo.vpnplugin

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * ProcessBuilder-based Go client bridge.
 *
 * Mirrors the architecture of the original proxy-turn-vk-android project:
 *   - Launches libclient.so as a separate OS process via ProcessBuilder.
 *   - Communicates via stdin (commands) / stdout (logs, stats, WireGuard config).
 *   - Runs a watchdog that detects dead/zombie processes and restarts them.
 *   - Supports pause() / resume() for network loss handling (keeps service alive).
 *
 * STDOUT protocol (parsed from Go process output):
 *   [СТАТИСТИКА] Активных: N, Bytes↑ X, Bytes↓ Y  → stats parsing
 *   ╔══ WireGuard Конфиг ══╗ ... ╚══╝              → WireGuard config delivery
 *   [LEVEL] [CATEGORY] message                      → log entries
 *
 * STDIN protocol (sent to Go process):
 *   "PAUSE\n"   → pause transport (network lost)
 *   "RESUME\n"  → resume transport (network restored)
 *   "STOP\n"    → graceful shutdown
 */
class GoProcessBridge(private val context: Context) {

    companion object {
        private const val TAG = "GoProcessBridge"
        private const val BINARY_NAME = "libclient.so"
        private const val WATCHDOG_INITIAL_DELAY_MS = 10_000L
        private const val WATCHDOG_INTERVAL_MS = 5_000L
        private const val ZOMBIE_TIMEOUT_MS = 90_000L
        private const val MAX_LOG_BUFFER = 1000
    }

    // ── Scope ─────────────────────────────────────────────────────────────────

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ── State ─────────────────────────────────────────────────────────────────

    @Volatile private var process: Process? = null
    private var readerJob: Job? = null
    private var watchdogJob: Job? = null

    val running = AtomicBoolean(false)
    val activeWorkers = AtomicInteger(0)

    // Stats (updated by stdout parser)
    val statsBytesIn  = AtomicLong(0)
    val statsBytesOut = AtomicLong(0)
    val statsPktsIn   = AtomicLong(0)
    val statsPktsOut  = AtomicLong(0)

    // ── Log buffer ────────────────────────────────────────────────────────────

    data class LogEntry(
        val id: String,
        val timestampMs: Long,
        val level: String,
        val category: String,
        val message: String,
        var repeatCount: Int = 1,
    )

    private val logBuffer = ConcurrentLinkedDeque<LogEntry>()

    fun drainLogs(): List<LogEntry> {
        val result = mutableListOf<LogEntry>()
        while (logBuffer.isNotEmpty()) result.add(logBuffer.pollFirst() ?: break)
        return result
    }

    fun clearLogs() = logBuffer.clear()

    // ── WireGuard config callback ─────────────────────────────────────────────

    /** Called on the IO dispatcher when a WireGuard config block is collected. */
    var onWireGuardConfig: ((configStr: String) -> Unit)? = null

    /** Called when an error causes a required stop (circuit breaker). */
    var onCriticalError: ((message: String) -> Unit)? = null

    /** Called when status changes (connecting / connected / reconnecting / failed). */
    var onStatusChange: ((status: String, error: String?) -> Unit)? = null

    // ── Current params ────────────────────────────────────────────────────────

    @Volatile private var currentParams: GoClientParams? = null
    @Volatile private var isSwitching = false

    // Error circuit-breaker counters
    private var floodCount = 0
    private var mismatchCount = 0
    private var refusedCount = 0

    // ── Start ─────────────────────────────────────────────────────────────────

    fun start(params: GoClientParams, switching: Boolean = false) {
        if (running.get() && !switching) {
            Log.w(TAG, "already running, ignoring start()")
            return
        }
        if (!switching) {
            clearLogs()
            statsBytesIn.set(0); statsBytesOut.set(0)
            statsPktsIn.set(0);  statsPktsOut.set(0)
            floodCount = 0; mismatchCount = 0; refusedCount = 0
            currentParams = params
        }
        isSwitching = switching

        scope.launch { launchProcess(params) }
    }

    private suspend fun launchProcess(params: GoClientParams) {
        val binaryPath = context.applicationInfo.nativeLibraryDir + "/$BINARY_NAME"
        val binaryFile = File(binaryPath)
        if (!binaryFile.exists()) {
            addLog("error", TAG, "Binary not found: $binaryPath")
            onCriticalError?.invoke("libclient.so not found. Run build_android_so.sh first.")
            running.set(false)
            return
        }

        val cmd = buildCommand(binaryPath, params)
        Log.d(TAG, "Launching: ${cmd.joinToString(" ")}")

        try {
            val pb = ProcessBuilder(cmd).apply {
                directory(context.filesDir)
                redirectErrorStream(true)
                environment()["LD_LIBRARY_PATH"] = context.applicationInfo.nativeLibraryDir
            }
            process = pb.start()
            running.set(true)
            onStatusChange?.invoke("connecting", null)
            startLogReader()
            startWatchdog(params)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch process: ${e.message}", e)
            addLog("error", TAG, "Launch failed: ${e.message}")
            running.set(false)
            onStatusChange?.invoke("failed", e.message)
        }
    }

    private fun buildCommand(binaryPath: String, params: GoClientParams): List<String> {
        return buildList {
            add(binaryPath)
            add("-peer");    add(params.peer)
            add("-listen");  add("127.0.0.1:${params.localPort}")
            add("-n");       add(params.workers.toString())
            add("-transport"); add(params.transportType)
            if (params.authToken.isNotEmpty()) { add("-password"); add(params.authToken) }
            if (params.deviceId.isNotEmpty())  { add("-device-id"); add(params.deviceId) }
            if (params.sni.isNotEmpty())        { add("-sni"); add(params.sni) }
            add("-mtu"); add(params.mtu.toString())
            add("-keepalive"); add(params.keepAliveSeconds.toString())
            add("-reconnects"); add(params.maxReconnects.toString())
            if (params.dns.isNotEmpty()) { add("-dns"); add(params.dns.joinToString(",")) }
            if (params.ipv4Address.isNotEmpty()) { add("-ipv4"); add(params.ipv4Address) }
            if (params.ipv4Mask.isNotEmpty())    { add("-mask"); add(params.ipv4Mask) }
            if (params.allowedRoutes.isNotEmpty()) { add("-allow"); add(params.allowedRoutes.joinToString(",")) }
            if (params.excludedRoutes.isNotEmpty()) { add("-exclude"); add(params.excludedRoutes.joinToString(",")) }
            if (params.transportType == "mock") add("-mock")
            if (!params.enableUDP && params.enableTCP) add("-tcp") else add("-udp")
            if (!params.autoReconnect) add("-no-reconnect")
        }
    }

    // ── Stdout reader ─────────────────────────────────────────────────────────

    private fun startLogReader() {
        readerJob?.cancel()
        readerJob = scope.launch {
            val reader = process?.inputStream?.let { BufferedReader(InputStreamReader(it)) }
                ?: return@launch

            var collectingConfig = false
            val configBuilder = StringBuilder()
            var lastErrorResetMs = System.currentTimeMillis()

            try {
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val raw = line ?: continue

                    // Periodic error counter reset (60s)
                    val now = System.currentTimeMillis()
                    if (now - lastErrorResetMs > 60_000) {
                        floodCount = 0; mismatchCount = 0; refusedCount = 0
                        lastErrorResetMs = now
                    }

                    // Strip Go date prefix: "2024/01/15 12:34:56.123456 "
                    val msg = raw.replace(
                        Regex("^\\d{4}/\\d{2}/\\d{2}\\s\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?\\s"), ""
                    ).trim()

                    // ── WireGuard config collection ──────────────────────────
                    if (raw.contains("╔") && raw.contains("WireGuard")) {
                        collectingConfig = true
                        configBuilder.clear()
                        continue
                    }
                    if (collectingConfig) {
                        if (raw.contains("╚")) {
                            collectingConfig = false
                            val cfg = configBuilder.toString().trim()
                            if (cfg.isNotEmpty()) {
                                addLog("info", "WireGuard", "Config received (${cfg.lines().size} lines)")
                                withContext(Dispatchers.Main) {
                                    onWireGuardConfig?.invoke(cfg)
                                }
                            }
                        } else if (raw.contains("║")) {
                            val content = raw.replace("║", "").trim()
                            if (content.isNotEmpty()) configBuilder.appendLine(content)
                        }
                        continue
                    }

                    // ── Stats line ────────────────────────────────────────────
                    if (msg.contains("[СТАТИСТИКА]")) {
                        parseStats(msg.substringAfter("[СТАТИСТИКА]").trim())
                        addLog("debug", "Stats", msg.substringAfter("[СТАТИСТИКА]").trim())
                        continue
                    }

                    // ── Circuit breaker ───────────────────────────────────────
                    val isError = msg.contains("error", ignoreCase = true) ||
                            msg.contains("timeout", ignoreCase = true) ||
                            msg.contains("refused", ignoreCase = true)

                    if (isError) {
                        when {
                            msg.contains("Flood", ignoreCase = true) -> {
                                floodCount++
                                if (floodCount >= 5) { handleCriticalError("Flood control. Try later."); continue }
                            }
                            msg.contains("ip mismatch", ignoreCase = true) -> {
                                mismatchCount++
                                if (mismatchCount >= 5) { handleCriticalError("IP mismatch. Reconnect."); continue }
                            }
                            msg.contains("connection refused", ignoreCase = true) ||
                            msg.contains("timeout", ignoreCase = true) -> {
                                refusedCount++
                                if (refusedCount >= 400) { handleCriticalError("Network unreachable (400+ timeouts)."); continue }
                            }
                        }
                    }

                    // ── Status lines ──────────────────────────────────────────
                    when {
                        msg.contains("transport connected", ignoreCase = true) -> {
                            onStatusChange?.invoke("connected", null)
                        }
                        msg.contains("reconnect", ignoreCase = true) -> {
                            onStatusChange?.invoke("reconnecting", null)
                        }
                        msg.contains("shutdown complete", ignoreCase = true) -> {
                            onStatusChange?.invoke("disconnected", null)
                        }
                    }

                    // ── Route to log buffer ───────────────────────────────────
                    val level = when {
                        msg.contains("[ERROR]")   || isError -> "error"
                        msg.contains("[WARNING]")            -> "warning"
                        msg.contains("[DEBUG]")              -> "debug"
                        else                                 -> "info"
                    }
                    val category = extractCategory(msg)
                    addLog(level, category, msg)
                }
            } catch (e: Exception) {
                if (running.get()) {
                    Log.e(TAG, "Log reader error: ${e.message}")
                    addLog("error", TAG, "Process output error: ${e.message}")
                }
            } finally {
                running.set(false)
                activeWorkers.set(0)
                Log.d(TAG, "Log reader finished")
            }
        }
    }

    private fun parseStats(stats: String) {
        // "[СТАТИСТИКА] Активных: N, Bytes↑ X, Bytes↓ Y, Pkts↑ P, Pkts↓ Q"
        Regex("Активных:\\s*(\\d+)").find(stats)?.let {
            activeWorkers.set(it.groupValues[1].toIntOrNull() ?: 0)
        }
        Regex("Bytes↑\\s*(\\d+)").find(stats)?.let {
            statsBytesOut.set(it.groupValues[1].toLongOrNull() ?: 0)
        }
        Regex("Bytes↓\\s*(\\d+)").find(stats)?.let {
            statsBytesIn.set(it.groupValues[1].toLongOrNull() ?: 0)
        }
        Regex("Pkts↑\\s*(\\d+)").find(stats)?.let {
            statsPktsOut.set(it.groupValues[1].toLongOrNull() ?: 0)
        }
        Regex("Pkts↓\\s*(\\d+)").find(stats)?.let {
            statsPktsIn.set(it.groupValues[1].toLongOrNull() ?: 0)
        }
    }

    private fun extractCategory(msg: String): String {
        val m = Regex("\\[([A-Za-z][A-Za-z0-9_/]+)]").find(msg)
        return m?.groupValues?.getOrNull(1) ?: "Go"
    }

    // ── Watchdog ──────────────────────────────────────────────────────────────

    private fun startWatchdog(params: GoClientParams) {
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            var zeroWorkersSince = 0L
            delay(WATCHDOG_INITIAL_DELAY_MS)

            while (isActive && running.get()) {
                val proc = process
                if (proc == null || !proc.isAlive) {
                    addLog("warning", TAG, "⚠ Process died. Restarting…")
                    activeWorkers.set(0)
                    killProcess()
                    delay(2000)
                    if (running.get()) {
                        onStatusChange?.invoke("reconnecting", null)
                        start(params, switching = true)
                    }
                    return@launch
                }

                // Zombie detection: alive but 0 workers for 90s
                val workers = activeWorkers.get()
                if (workers <= 0) {
                    if (zeroWorkersSince == 0L) zeroWorkersSince = System.currentTimeMillis()
                    else if (System.currentTimeMillis() - zeroWorkersSince > ZOMBIE_TIMEOUT_MS) {
                        addLog("warning", TAG, "⚠ Zombie process (0 workers 90s). Restarting…")
                        killProcess()
                        delay(2000)
                        if (running.get()) {
                            onStatusChange?.invoke("reconnecting", null)
                            start(params, switching = true)
                        }
                        return@launch
                    }
                } else {
                    zeroWorkersSince = 0L
                }

                delay(WATCHDOG_INTERVAL_MS)
            }
        }
    }

    // ── Pause / Resume (network loss handling) ────────────────────────────────

    /**
     * Pause: kills the Go process without setting running=false.
     * The service stays alive; WireGuard tunnel stays up.
     * Called when all non-VPN networks are lost (Android Doze / airplane mode).
     */
    fun pause() {
        if (!running.get()) return
        Log.d(TAG, "pause() — killing Go process, keeping running=true")
        killProcess()
        activeWorkers.set(0)
        addLog("info", TAG, "Tunnel paused (network lost)")
    }

    /**
     * Resume: restarts the Go process with the same params.
     * Called when a non-VPN internet network becomes available again.
     */
    fun resume() {
        val params = currentParams ?: return
        Log.d(TAG, "resume() — restarting Go process")
        addLog("info", TAG, "Tunnel resuming (network restored)")
        scope.launch { start(params, switching = true) }
    }

    /**
     * Restart transport: soft restart for network change (e.g., Wi-Fi → LTE).
     * Has 5-second cooldown to avoid rapid restarts.
     */
    fun restartTransport() {
        val params = currentParams ?: return
        addLog("info", TAG, "[NET] Restarting transport due to network change…")
        killProcess()
        scope.launch {
            delay(1500)
            start(params, switching = true)
        }
    }

    // ── Stop ──────────────────────────────────────────────────────────────────

    fun stop() {
        Log.d(TAG, "stop()")
        sendStdin("STOP")
        scope.launch {
            delay(500)
            killProcess()
        }
        running.set(false)
        activeWorkers.set(0)
        currentParams = null
        onStatusChange?.invoke("disconnected", null)
    }

    suspend fun stopAndWait() {
        sendStdin("STOP")
        withContext(Dispatchers.IO) {
            delay(500)
            killProcess()
            running.set(false)
            activeWorkers.set(0)
            currentParams = null
            // Wait for port 9000 to be freed (up to 3s)
            repeat(30) {
                try {
                    java.net.ServerSocket(9000, 1,
                        java.net.InetAddress.getByName("127.0.0.1")).use { it.close() }
                    return@withContext
                } catch (_: Exception) { delay(100) }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun sendStdin(command: String) {
        val proc = process ?: return
        if (!proc.isAlive) return
        try {
            proc.outputStream.write("$command\n".toByteArray(Charsets.UTF_8))
            proc.outputStream.flush()
        } catch (e: Exception) {
            Log.w(TAG, "sendStdin($command) error: ${e.message}")
        }
    }

    private fun killProcess() {
        watchdogJob?.cancel()
        readerJob?.cancel()
        val proc = process
        process = null
        if (proc != null) {
            try { proc.destroy() } catch (_: Exception) {}
            try { proc.waitFor(500, java.util.concurrent.TimeUnit.MILLISECONDS) } catch (_: Exception) {}
            if (proc.isAlive) {
                try { proc.destroyForcibly() } catch (_: Exception) {}
                try { proc.waitFor(1000, java.util.concurrent.TimeUnit.MILLISECONDS) } catch (_: Exception) {}
            }
        }
    }

    private fun handleCriticalError(message: String) {
        addLog("error", TAG, "[STOP] $message")
        stop()
        onCriticalError?.invoke(message)
    }

    private fun addLog(level: String, category: String, message: String) {
        val last = logBuffer.peekLast()
        if (last != null && last.level == level &&
            last.category == category && last.message == message) {
            last.repeatCount++
            return
        }
        if (logBuffer.size >= MAX_LOG_BUFFER) logBuffer.pollFirst()
        logBuffer.addLast(LogEntry(
            id = UUID.randomUUID().toString(),
            timestampMs = System.currentTimeMillis(),
            level = level, category = category, message = message,
        ))
    }

    fun statsJSON(): String {
        return """{"bytesIn":${statsBytesIn.get()},"bytesOut":${statsBytesOut.get()},"packetsIn":${statsPktsIn.get()},"packetsOut":${statsPktsOut.get()},"activeStreams":${activeWorkers.get()}}"""
    }
}

// ── GoClientParams ────────────────────────────────────────────────────────────

data class GoClientParams(
    val peer: String,
    val localPort: Int = 9000,
    val workers: Int = 4,
    val transportType: String = "mock",
    val authToken: String = "",
    val deviceId: String = "",
    val sni: String = "",
    val mtu: Int = 1280,
    val keepAliveSeconds: Int = 25,
    val maxReconnects: Int = 3,
    val autoReconnect: Boolean = true,
    val dns: List<String> = listOf("1.1.1.1", "8.8.8.8"),
    val ipv4Address: String = "10.7.0.2",
    val ipv4Mask: String = "255.255.255.0",
    val allowedRoutes: List<String> = listOf("0.0.0.0/0"),
    val excludedRoutes: List<String> = emptyList(),
    val enableUDP: Boolean = true,
    val enableTCP: Boolean = true,
)
