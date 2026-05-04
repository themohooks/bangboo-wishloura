package com.example.fluttervpngo.vpnplugin

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import com.wireguard.config.InetNetwork
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream

/**
 * Manages the WireGuard GoBackend tunnel lifecycle.
 *
 * Mirrors WireGuardHelper.kt from proxy-turn-vk-android.
 *
 * Flow:
 *   1. Go process (GoProcessBridge) delivers a WireGuard config string via stdout.
 *   2. AndroidVpnService calls WireGuardHelper.startTunnel(configStr).
 *   3. WireGuardHelper parses the config, applies app exclusions, brings up GoBackend.
 *   4. WireGuard GoBackend creates the TUN interface and manages crypto.
 *   5. The WG peer endpoint points to 127.0.0.1:<localPort> (the Go process).
 *
 * App exclusions:
 *   - Always excluded: this app's package + any packages in exclusionSet
 *   - excludeApplications() (blacklist) — excluded packages bypass the tunnel
 *   - For whitelist mode: call with the complement of the desired set
 */
class WireGuardHelper(private val context: Context) {

    companion object {
        private const val TAG = "WireGuardHelper"
        private val wgMutex = Mutex()
        @Volatile private var sharedTunnel: WgTunnel? = null
    }

    private val appContext = context.applicationContext
    private val backend: GoBackend by lazy {
        (appContext as? VpnGoApplication)?.getGoBackend(context)
            ?: GoBackend(appContext)
    }

    class WgTunnel : Tunnel {
        override fun getName() = "fluttervpngo"
        override fun onStateChange(newState: Tunnel.State) {
            Log.d("WgTunnel", "State → $newState")
        }
    }

    // ── Start ─────────────────────────────────────────────────────────────────

    suspend fun startTunnel(
        configString: String,
        excludedPackages: Set<String> = emptySet(),
    ) = wgMutex.withLock {
        startTunnelLocked(configString, excludedPackages)
    }

    private suspend fun startTunnelLocked(
        configString: String,
        excludedPackages: Set<String>,
    ) = withContext(Dispatchers.IO) {
        try {
            // Verify VPN permission
            if (VpnService.prepare(appContext) != null) {
                throw IllegalStateException("VPN permission not granted")
            }

            ensureGoBackendServiceStarted()

            // Tear down existing tunnel
            sharedTunnel?.let { existing ->
                runCatching { backend.setState(existing, Tunnel.State.DOWN, null) }
                sharedTunnel = null
                delay(150)
            }

            // Parse WireGuard config
            val parsed = Config.parse(ByteArrayInputStream(configString.toByteArray(Charsets.UTF_8)))

            // Build Interface section
            val ifBuilder = Interface.Builder()
                .parseAddresses(
                    parsed.`interface`.addresses.joinToString(", ") { it.toString() }
                )

            if (parsed.`interface`.dnsServers.isNotEmpty()) {
                ifBuilder.parseDnsServers(
                    parsed.`interface`.dnsServers.joinToString(", ") { it.hostAddress ?: "" }
                )
            }
            parsed.`interface`.listenPort.ifPresent { port ->
                ifBuilder.parseListenPort(port.toString())
            }

            // MTU: use server value but at least 1280 for mobile networks
            val mtu = parsed.`interface`.mtu
                .map { it.coerceAtLeast(1280) }
                .orElse(1280)
            ifBuilder.parseMtu(mtu.toString())

            ifBuilder.parsePrivateKey(parsed.`interface`.keyPair.privateKey.toBase64())

            // App exclusions: always exclude own app
            val excluded = mutableSetOf(appContext.packageName)
            excluded.addAll(excludedPackages)
            val installedExcluded = excluded.filter { isInstalled(it) }.toSet()
            if (installedExcluded.isNotEmpty()) {
                ifBuilder.excludeApplications(installedExcluded)
                Log.d(TAG, "Excluding ${installedExcluded.size} apps from tunnel")
            }

            val finalInterface = ifBuilder.build()

            // Build Peer section
            val peer = parsed.peers.firstOrNull()
                ?: throw IllegalStateException("WireGuard config has no peer section")

            val peerBuilder = Peer.Builder().apply {
                parsePublicKey(peer.publicKey.toBase64())
                peer.preSharedKey.ifPresent { parsePreSharedKey(it.toBase64()) }
                peer.endpoint.ifPresent  { parseEndpoint(it.toString()) }
                peer.persistentKeepalive.ifPresent { parsePersistentKeepalive(it.toString()) }
                // Route all traffic through the tunnel (exclusions handled above)
                parseAllowedIPs("0.0.0.0/0")
            }

            val finalConfig = Config.Builder()
                .setInterface(finalInterface)
                .addPeer(peerBuilder.build())
                .build()

            val tunnel = WgTunnel()
            setTunnelUpWithRetry(tunnel, finalConfig)
            sharedTunnel = tunnel

            Log.i(TAG, "WireGuard tunnel started (excluded=${installedExcluded.size} apps)")
        } catch (e: Exception) {
            val detail = "WireGuard start failed: ${e.readableMessage()}"
            Log.e(TAG, "$detail\nConfig preview: ${configString.take(200)}")
            throw IllegalStateException(detail, e)
        }
    }

    // ── Reload (for exclusion changes) ────────────────────────────────────────

    suspend fun reloadTunnel(excludedPackages: Set<String>) = wgMutex.withLock {
        withContext(Dispatchers.IO) {
            val tunnel = sharedTunnel ?: return@withContext
            val cfg = lastConfigString ?: return@withContext
            try {
                backend.setState(tunnel, Tunnel.State.DOWN, null)
                sharedTunnel = null
                delay(150)
                startTunnelLocked(cfg, excludedPackages)
                Log.d(TAG, "WireGuard tunnel reloaded (new exclusions)")
            } catch (e: Exception) {
                Log.e(TAG, "Reload failed: ${e.readableMessage()}")
            }
        }
    }

    // ── Stop ──────────────────────────────────────────────────────────────────

    suspend fun stopTunnel() = wgMutex.withLock {
        withContext(Dispatchers.IO) {
            runCatching {
                sharedTunnel?.let {
                    backend.setState(it, Tunnel.State.DOWN, null)
                    sharedTunnel = null
                    Log.i(TAG, "WireGuard tunnel stopped")
                }
            }.onFailure { Log.e(TAG, "Stop failed: ${it.readableMessage()}") }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @Volatile private var lastConfigString: String? = null

    private suspend fun ensureGoBackendServiceStarted() {
        withContext(Dispatchers.Main) {
            runCatching {
                val intent = Intent(appContext, GoBackend.VpnService::class.java)
                appContext.startService(intent)
            }
        }
        delay(300)
    }

    private suspend fun setTunnelUpWithRetry(tunnel: WgTunnel, config: Config) {
        var lastError: Exception? = null
        repeat(3) { attempt ->
            try {
                backend.setState(tunnel, Tunnel.State.UP, config)
                return
            } catch (e: Exception) {
                lastError = e
                Log.w(TAG, "UP attempt ${attempt + 1}/3 failed: ${e.readableMessage()}")
                runCatching { backend.setState(tunnel, Tunnel.State.DOWN, null) }
                ensureGoBackendServiceStarted()
                delay(250L * (attempt + 1))
            }
        }
        throw lastError ?: IllegalStateException("WireGuard UP failed after 3 attempts")
    }

    private fun isInstalled(packageName: String): Boolean =
        runCatching { appContext.packageManager.getPackageInfo(packageName, 0); true }
            .getOrDefault(false)

    private fun Throwable.readableMessage(): String {
        val text = message ?: localizedMessage
        return if (text.isNullOrBlank()) this::class.java.simpleName
        else "${this::class.java.simpleName}: $text"
    }
}

// ── Application interface for GoBackend singleton ─────────────────────────────

/**
 * Your Application class should implement this interface to provide
 * a shared GoBackend instance (same pattern as WdttApplication in original).
 */
interface VpnGoApplication {
    fun getGoBackend(context: Context): GoBackend
}
