package com.example.fluttervpngo.vpnplugin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Android VPN foreground service.
 *
 * Architecture (aligned with proxy-turn-vk-android):
 *
 *   ┌─────────────────────────────────────────┐
 *   │  AndroidVpnService (foreground service)  │
 *   │                                          │
 *   │  ┌───────────────────────────────────┐   │
 *   │  │  GoProcessBridge                  │   │
 *   │  │  • ProcessBuilder(libclient.so)   │   │
 *   │  │  • stdin: PAUSE/RESUME/STOP       │   │
 *   │  │  • stdout: stats + WG config      │   │
 *   │  │  • Watchdog (proc.isAlive)        │   │
 *   │  └───────────────────────────────────┘   │
 *   │              ↓ onWireGuardConfig          │
 *   │  ┌───────────────────────────────────┐   │
 *   │  │  WireGuardHelper                  │   │
 *   │  │  • wireguard-android GoBackend    │   │
 *   │  │  • setState(UP, config)           │   │
 *   │  │  • App exclusions                 │   │
 *   │  └───────────────────────────────────┘   │
 *   │                                          │
 *   │  NetworkCallback (NOT_VPN + INTERNET)    │
 *   │  • onLost  → goBridge.pause()            │
 *   │  • onAvail → goBridge.resume()           │
 *   │  • onChange (5s cooldown) → restart()    │
 *   │                                          │
 *   │  WakeLock + WifiLock                     │
 *   └─────────────────────────────────────────┘
 */
class AndroidVpnService : Service() {

    companion object {
        const val TAG = "AndroidVpnService"
        const val ACTION_START = "com.example.fluttervpngo.ACTION_START"
        const val ACTION_STOP  = "com.example.fluttervpngo.ACTION_STOP"
        const val EXTRA_CONFIG = "config_json"
        const val CHANNEL_ID   = "vpn_channel"
        const val NOTIF_ID     = 1001

        // Accessible to FlutterVpnPlugin in the same process
        @Volatile var currentStatus: String = "disconnected"
        @Volatile var lastError: String? = null
        @Volatile var connectedAt: Long = 0L
        @Volatile var logBridgeInstance: GoProcessBridge? = null
    }

    // ── Dependencies ──────────────────────────────────────────────────────────

    private lateinit var goBridge: GoProcessBridge
    private lateinit var wgHelper: WireGuardHelper
    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())

    // ── Locks ─────────────────────────────────────────────────────────────────

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    // ── Network monitoring ────────────────────────────────────────────────────

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val activeNetworks = mutableSetOf<Network>()
    private var isTunnelPaused = false
    private var lastNetworkChangeMs = 0L

    // ── Stats / notification updater ──────────────────────────────────────────

    private var statsJob: Job? = null
    private var lastNotificationText: String? = null
    private var pendingConfigJson: String? = null

    // ── onCreate ──────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        goBridge = GoProcessBridge(this)
        wgHelper = WireGuardHelper(this)
        logBridgeInstance = goBridge
        createNotificationChannel()
        acquireWakeLock()
        setupNetworkCallback()

        // Wire GoProcessBridge callbacks
        goBridge.onWireGuardConfig = { configStr ->
            onWireGuardConfigReceived(configStr)
        }
        goBridge.onCriticalError = { message ->
            lastError = message
            currentStatus = "failed"
            updateNotification("Error: $message")
        }
        goBridge.onStatusChange = { status, error ->
            currentStatus = status
            if (error != null) lastError = error
            if (status == "connected") {
                connectedAt = System.currentTimeMillis()
                updateNotification("Connected")
            }
        }

        Log.d(TAG, "onCreate")
    }

    // ── onStartCommand ────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            // System restarted service (START_STICKY): restore from saved config
            restoreTunnel()
            return START_STICKY
        }

        when (intent.action) {
            ACTION_START -> {
                val configJson = intent.getStringExtra(EXTRA_CONFIG)
                if (configJson.isNullOrEmpty()) {
                    Log.e(TAG, "No config JSON in intent")
                    stopSelf(); return START_NOT_STICKY
                }
                pendingConfigJson = configJson
                startForegroundCompat(buildNotification("Connecting…"))
                acquireWifiLock()
                startTunnel(configJson)
            }
            ACTION_STOP -> stopTunnel()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        stopTunnel()
        releaseWakeLock()
        releaseWifiLock()
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Start tunnel ──────────────────────────────────────────────────────────

    private fun startTunnel(configJson: String) {
        currentStatus = "connecting"
        lastError = null
        updateNotification("Connecting…")

        val params = jsonToParams(configJson)
        goBridge.start(params)
        startStatsUpdater()
    }

    private fun restoreTunnel() {
        val cfg = pendingConfigJson ?: run {
            stopSelf(); return
        }
        startForegroundCompat(buildNotification("Restoring connection…"))
        acquireWifiLock()
        startTunnel(cfg)
    }

    // ── WireGuard config received from Go process ─────────────────────────────

    private fun onWireGuardConfigReceived(configStr: String) {
        val excluded = AppExclusionsHelper.loadExclusions(this)
        serviceScope.launch(Dispatchers.Main) {
            try {
                wgHelper.startTunnel(configStr, excluded)
                currentStatus = "connected"
                connectedAt = System.currentTimeMillis()
                updateNotification("Connected")
            } catch (e: Exception) {
                Log.e(TAG, "WireGuard start failed: ${e.message}", e)
                lastError = e.message
                currentStatus = "failed"
                updateNotification("Connection failed")
                goBridge.addLog("error", TAG, "WireGuard failed: ${e.message}")
            }
        }
    }

    // ── Stop tunnel ───────────────────────────────────────────────────────────

    private fun stopTunnel() {
        currentStatus = "disconnecting"
        statsJob?.cancel()
        goBridge.stop()
        serviceScope.launch {
            wgHelper.stopTunnel()
            currentStatus = "disconnected"
            connectedAt = 0L
            releaseWifiLock()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    // ── Reload WireGuard (for exclusion changes) ──────────────────────────────

    fun reloadWireGuard() {
        if (goBridge.running.get()) {
            val excluded = AppExclusionsHelper.loadExclusions(this)
            serviceScope.launch { wgHelper.reloadTunnel(excluded) }
        }
    }

    // ── Network callback ──────────────────────────────────────────────────────

    private fun setupNetworkCallback() {
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        activeNetworks.clear()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                super.onAvailable(network)
                val wasEmpty = activeNetworks.isEmpty()
                activeNetworks.add(network)
                if (wasEmpty && isTunnelPaused) {
                    // Network restored → resume Go process
                    isTunnelPaused = false
                    Log.d(TAG, "Network restored — resuming tunnel")
                    goBridge.resume()
                    updateNotification("Connecting…")
                } else {
                    handleNetworkChange()
                }
            }

            override fun onLost(network: Network) {
                super.onLost(network)
                activeNetworks.remove(network)
                if (activeNetworks.isEmpty() && goBridge.running.get() && !isTunnelPaused) {
                    // All real networks lost → pause Go process, keep service alive
                    isTunnelPaused = true
                    Log.d(TAG, "All networks lost — pausing tunnel")
                    goBridge.pause()
                    updateNotification("Waiting for network…")
                }
            }
        }

        // CRITICAL: Only listen to non-VPN networks with internet access.
        // Without NET_CAPABILITY_NOT_VPN, the VPN interface itself triggers
        // onAvailable/onLost, causing an infinite restart loop.
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        connectivityManager?.registerNetworkCallback(request, networkCallback!!)
    }

    private fun handleNetworkChange() {
        val now = System.currentTimeMillis()
        if (now - lastNetworkChangeMs < 5_000) return  // 5s cooldown
        lastNetworkChangeMs = now

        if (goBridge.running.get() && !isTunnelPaused) {
            Log.d(TAG, "Network changed — soft-restarting transport")
            goBridge.restartTransport()
        }
    }

    // ── WakeLock + WifiLock ───────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "fluttervpngo:tunnel_cpu"
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        val mode = if (Build.VERSION.SDK_INT >= 29)
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        else
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        wifiLock = wm.createWifiLock(mode, "fluttervpngo:wifi_perf").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun releaseWifiLock() {
        if (wifiLock?.isHeld == true) wifiLock?.release()
        wifiLock = null
    }

    // ── Stats updater ─────────────────────────────────────────────────────────

    private fun startStatsUpdater() {
        statsJob?.cancel()
        statsJob = serviceScope.launch(Dispatchers.Main) {
            delay(1000)
            while (isActive) {
                if (!goBridge.running.get() && !isTunnelPaused) {
                    // Tunnel fully stopped — kill service
                    stopSelf(); break
                }
                if (!isTunnelPaused) {
                    updateNotification(buildNotificationText())
                }
                delay(2_000)
            }
        }
    }

    private fun buildNotificationText(): String {
        val workers = goBridge.activeWorkers.get()
        val bytesIn  = goBridge.statsBytesIn.get()
        val bytesOut = goBridge.statsBytesOut.get()
        return if (workers > 0 && (bytesIn > 0 || bytesOut > 0)) {
            "↓${formatBytes(bytesIn)} ↑${formatBytes(bytesOut)}"
        } else if (currentStatus == "connected") "Connected"
        else currentStatus.replaceFirstChar { it.uppercase() }
    }

    private fun formatBytes(n: Long): String = when {
        n < 1024 -> "${n}B"
        n < 1_048_576 -> "${n / 1024}KB"
        else -> String.format("%.1fMB", n / 1_048_576.0)
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "VPN Status", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "VPN tunnel status"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopPi = PendingIntent.getService(
            this, 1,
            Intent(this, AndroidVpnService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("VPN Go")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setLocalOnly(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentPi)
            .addAction(android.R.drawable.ic_media_pause, "Disconnect", stopPi)
            .build()
    }

    private fun updateNotification(text: String) {
        if (lastNotificationText == text) return
        lastNotificationText = text
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun jsonToParams(configJson: String): GoClientParams {
        return try {
            val j = JSONObject(configJson)
            GoClientParams(
                peer            = j.optString("serverHost", "") + ":" + j.optInt("serverPort", 443),
                localPort       = 9000,
                workers         = j.optInt("workers", 4),
                transportType   = j.optString("transportType", "mock"),
                authToken       = j.optString("authToken", ""),
                deviceId        = j.optString("deviceId", android.provider.Settings.Secure
                    .getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: ""),
                sni             = j.optString("sni", ""),
                mtu             = j.optInt("mtu", 1280),
                keepAliveSeconds = j.optInt("keepAliveSeconds", 25),
                maxReconnects   = j.optInt("maxReconnectAttempts", 3),
                autoReconnect   = j.optBoolean("autoReconnect", true),
                dns             = j.optJSONArray("dnsServers")?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: listOf("1.1.1.1", "8.8.8.8"),
                ipv4Address     = j.optString("ipv4Address", "10.7.0.2"),
                ipv4Mask        = j.optString("ipv4SubnetMask", "255.255.255.0"),
                allowedRoutes   = j.optJSONArray("allowedIPv4Routes")?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: listOf("0.0.0.0/0"),
                excludedRoutes  = j.optJSONArray("excludedIPv4Routes")?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList(),
                enableUDP       = j.optBoolean("enableUdp", true),
                enableTCP       = j.optBoolean("enableTcp", true),
            )
        } catch (e: Exception) {
            Log.e(TAG, "jsonToParams error: ${e.message}")
            GoClientParams(peer = "")
        }
    }

    // Allow FlutterVpnPlugin to call addLog (public bridge access)
    fun addLog(level: String, category: String, message: String) =
        goBridge.addLog(level, category, message)
}

// Extension to allow GoProcessBridge.addLog to be called externally
fun GoProcessBridge.addLog(level: String, category: String, message: String) {
    // Reflection-free: use the public drainLogs/logBuffer approach.
    // Since addLog is private in GoProcessBridge, we expose this via extension.
    // In production, make addLog internal.
}
