package com.example.fluttervpngo.vpnplugin

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Flutter plugin implementing the Pigeon VpnHostApi.
 *
 * Android-specific notes:
 *  - Commands (prepareVpn, startTunnel, stopTunnel, etc.) delegate to AndroidVpnService.
 *  - Status / stats / logs are read from AndroidVpnService static state and
 *    GoProcessBridge log buffer.
 *  - App exclusions are read/written via AppExclusionsHelper (SharedPreferences).
 *  - EventChannels push status/stats/log events to Flutter reactively.
 */
class FlutterVpnPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    VpnHostApi {

    companion object {
        private const val TAG = "FlutterVpnPlugin"
        private const val VPN_REQUEST_CODE = 0x0F00

        private const val STATUS_CHANNEL = "com.example.fluttervpngo/vpn_status_events"
        private const val STATS_CHANNEL  = "com.example.fluttervpngo/vpn_stats_events"
        private const val LOG_CHANNEL    = "com.example.fluttervpngo/vpn_log_events"
    }

    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // EventChannel sinks
    private var statusSink: EventChannel.EventSink? = null
    private var statsSink:  EventChannel.EventSink? = null
    private var logSink:    EventChannel.EventSink? = null

    private var prepareCallback: ((Result<Boolean>) -> Unit)? = null
    private var pendingConfigJson: String? = null

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        VpnHostApi.setUp(binding.binaryMessenger, this)

        EventChannel(binding.binaryMessenger, STATUS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(a: Any?, s: EventChannel.EventSink?) { statusSink = s }
                override fun onCancel(a: Any?) { statusSink = null }
            }
        )
        EventChannel(binding.binaryMessenger, STATS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(a: Any?, s: EventChannel.EventSink?) { statsSink = s }
                override fun onCancel(a: Any?) { statsSink = null }
            }
        )
        EventChannel(binding.binaryMessenger, LOG_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(a: Any?, s: EventChannel.EventSink?) { logSink = s }
                override fun onCancel(a: Any?) { logSink = null }
            }
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        VpnHostApi.setUp(binding.binaryMessenger, null)
        context = null
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }
    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null; activityBinding = null
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)

    // ── ActivityResultListener ────────────────────────────────────────────────

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_REQUEST_CODE) return false
        prepareCallback?.let { cb ->
            prepareCallback = null
            cb(Result.success(resultCode == Activity.RESULT_OK))
        }
        return true
    }

    // ── VpnHostApi ────────────────────────────────────────────────────────────

    override fun prepareVpn(callback: (Result<Boolean>) -> Unit) {
        val ctx = context ?: return callback(Result.failure(Exception("No context")))
        val intent = VpnService.prepare(ctx)
        if (intent == null) {
            callback(Result.success(true))
        } else {
            val act = activity ?: return callback(Result.failure(Exception("No activity for VPN dialog")))
            prepareCallback = callback
            act.startActivityForResult(intent, VPN_REQUEST_CODE)
        }
    }

    override fun installOrUpdateProfile(config: TunnelConfigDto, callback: (Result<Unit>) -> Unit) {
        try {
            pendingConfigJson = configDtoToJson(config)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun startTunnel(callback: (Result<Unit>) -> Unit) {
        val ctx = context ?: return callback(Result.failure(Exception("No context")))
        val cfg = pendingConfigJson ?: return callback(Result.failure(Exception("No config. Call installOrUpdateProfile first.")))
        try {
            val intent = Intent(ctx, AndroidVpnService::class.java).apply {
                action = AndroidVpnService.ACTION_START
                putExtra(AndroidVpnService.EXTRA_CONFIG, cfg)
            }
            ctx.startForegroundService(intent)
            callback(Result.success(Unit))
            pushStatus("connecting")
        } catch (e: Exception) {
            Log.e(TAG, "startTunnel: ${e.message}", e)
            callback(Result.failure(e))
        }
    }

    override fun stopTunnel(callback: (Result<Unit>) -> Unit) {
        val ctx = context ?: return callback(Result.failure(Exception("No context")))
        try {
            ctx.startService(Intent(ctx, AndroidVpnService::class.java).apply {
                action = AndroidVpnService.ACTION_STOP
            })
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun getStatus(callback: (Result<TunnelStatusDto>) -> Unit) {
        val status = AndroidVpnService.currentStatus
        val uptime = if (status == "connected" && AndroidVpnService.connectedAt > 0L)
            ((System.currentTimeMillis() - AndroidVpnService.connectedAt) / 1000).toLong()
        else null
        val cfg = pendingConfigJson
        val host      = cfg?.let { safeJson(it, "serverHost") }
        val transport = cfg?.let { safeJson(it, "transportType") }

        callback(Result.success(TunnelStatusDto(
            status        = status,
            lastError     = AndroidVpnService.lastError,
            serverHost    = host,
            transportType = transport,
            uptimeSeconds = uptime,
        )))
        // Push to EventChannel as well
        pushStatus(status, AndroidVpnService.lastError)
    }

    override fun getStats(callback: (Result<TrafficStatsDto>) -> Unit) {
        val bridge = AndroidVpnService.logBridgeInstance
        if (bridge != null) {
            callback(Result.success(TrafficStatsDto(
                bytesIn      = bridge.statsBytesIn.get(),
                bytesOut     = bridge.statsBytesOut.get(),
                packetsIn    = bridge.statsPktsIn.get(),
                packetsOut   = bridge.statsPktsOut.get(),
                activeStreams = bridge.activeWorkers.get().toLong(),
                updatedAtMs  = System.currentTimeMillis(),
            )))
        } else {
            callback(Result.success(TrafficStatsDto(0,0,0,0,0, System.currentTimeMillis())))
        }
    }

    override fun getLogs(callback: (Result<List<LogEntryDto?>>) -> Unit) {
        val entries = AndroidVpnService.logBridgeInstance?.drainLogs() ?: emptyList()
        callback(Result.success(entries.map { e ->
            LogEntryDto(e.id, e.timestampMs, e.level, e.category, e.message, e.repeatCount.toLong())
        }))
    }

    override fun clearLogs(callback: (Result<Unit>) -> Unit) {
        AndroidVpnService.logBridgeInstance?.clearLogs()
        callback(Result.success(Unit))
    }

    override fun getDiagnostics(callback: (Result<DiagnosticsDto>) -> Unit) {
        val ctx = context ?: return callback(Result.failure(Exception("No context")))
        try {
            val pm = ctx.packageManager
            val pkgInfo = pm.getPackageInfo(ctx.packageName, 0)
            val vpnGranted = VpnService.prepare(ctx) == null
            val build = android.os.Build.VERSION.RELEASE
            val sdk   = android.os.Build.VERSION.SDK_INT
            val model = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"

            callback(Result.success(DiagnosticsDto(
                platform               = "android",
                appVersion             = pkgInfo.versionName ?: "unknown",
                buildNumber            = pkgInfo.longVersionCode.toString(),
                osVersion              = "Android $build (SDK $sdk)",
                deviceModel            = model,
                vpnPermissionGranted   = vpnGranted,
                networkExtensionStatus = "n/a",
                runnerBundleId         = ctx.packageName,
                extensionBundleId      = "${ctx.packageName}.PacketTunnel",
                appGroupId             = "n/a",
                goClientVersion        = "1.0.0-mock (process)",
                keychainAccessGroup    = "n/a",
            )))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun sendProviderMessage(type: String, payload: Map<String, Any?>, callback: (Result<Unit>) -> Unit) {
        Log.d(TAG, "sendProviderMessage: $type / $payload")
        callback(Result.success(Unit))
    }

    // ── App exclusions API ────────────────────────────────────────────────────

    override fun getInstalledApps(callback: (Result<List<AppInfoDto?>>) -> Unit) {
        val ctx = context ?: return callback(Result.failure(Exception("No context")))
        scope.launch(Dispatchers.IO) {
            val apps = AppExclusionsHelper.getInstalledApps(ctx)
            val excluded = AppExclusionsHelper.loadExclusions(ctx)
            val isWhitelist = AppExclusionsHelper.loadIsWhitelist(ctx)
            scope.launch(Dispatchers.Main) {
                callback(Result.success(apps.map { a ->
                    AppInfoDto(
                        packageName = a.packageName,
                        label       = a.label,
                        iconBase64  = a.iconBase64,
                        isExcluded  = excluded.contains(a.packageName),
                        isWhitelist = isWhitelist,
                    )
                }))
            }
        }
    }

    override fun setExcludedApps(packages: List<String?>, isWhitelist: Boolean, callback: (Result<Unit>) -> Unit) {
        val ctx = context ?: return callback(Result.failure(Exception("No context")))
        val set = packages.filterNotNull().toSet()
        AppExclusionsHelper.saveExclusions(ctx, set)
        AppExclusionsHelper.saveIsWhitelist(ctx, isWhitelist)
        // Live-reload WireGuard tunnel if running
        scope.launch(Dispatchers.IO) {
            // Signal service to reload
            ctx.startService(Intent(ctx, AndroidVpnService::class.java).apply {
                action = "com.example.fluttervpngo.ACTION_RELOAD_WG"
            })
        }
        callback(Result.success(Unit))
    }

    // ── Push helpers ──────────────────────────────────────────────────────────

    private fun pushStatus(status: String, error: String? = null) {
        val cfg = pendingConfigJson
        val map = mapOf<String, Any?>(
            "status"        to status,
            "lastError"     to error,
            "serverHost"    to cfg?.let { safeJson(it, "serverHost") },
            "transportType" to cfg?.let { safeJson(it, "transportType") },
        )
        activity?.runOnUiThread { statusSink?.success(map) }
    }

    // ── Serialization ─────────────────────────────────────────────────────────

    private fun configDtoToJson(dto: TunnelConfigDto): String = JSONObject().apply {
        put("id",                   dto.id)
        put("name",                 dto.name)
        put("serverHost",           dto.serverHost)
        put("serverPort",           dto.serverPort)
        put("transportType",        dto.transportType)
        put("authToken",            dto.authToken ?: "")
        put("deviceId",             dto.deviceId)
        put("mtu",                  dto.mtu)
        put("dnsServers",           org.json.JSONArray(dto.dnsServers.filterNotNull()))
        put("ipv4Address",          dto.ipv4Address)
        put("ipv4SubnetMask",       dto.ipv4SubnetMask)
        put("allowedIPv4Routes",    org.json.JSONArray(dto.allowedIPv4Routes.filterNotNull()))
        put("excludedIPv4Routes",   org.json.JSONArray(dto.excludedIPv4Routes.filterNotNull()))
        put("keepAliveSeconds",     dto.keepAliveSeconds)
        put("workers",              dto.workers)
        put("sni",                  dto.sni ?: "")
        put("enableUdp",            dto.enableUdp)
        put("enableTcp",            dto.enableTcp)
        put("autoReconnect",        dto.autoReconnect)
        put("maxReconnectAttempts", dto.maxReconnectAttempts)
    }.toString()

    private fun safeJson(json: String, key: String): String? =
        runCatching { JSONObject(json).optString(key).ifEmpty { null } }.getOrNull()
}
