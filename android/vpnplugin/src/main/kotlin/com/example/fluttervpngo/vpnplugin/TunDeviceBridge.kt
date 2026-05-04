package com.example.fluttervpngo.vpnplugin

import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges the OS TUN device (via ParcelFileDescriptor) with the Go client.
 *
 * Two background threads are started:
 *  1. tunToGo  — reads IP packets from TUN fd → writes to Go client WritePacket
 *  2. goToTun  — reads IP packets from Go client ReadPacket → writes to TUN fd
 *
 * The loop stops when stop() is called or when the underlying fd is closed.
 */
class TunDeviceBridge(
    private val tunFd: ParcelFileDescriptor,
    private val goBridge: GoClientBridge,
    private val mtu: Int = 1280,
) {
    companion object {
        private const val TAG = "TunDeviceBridge"
    }

    private val running = AtomicBoolean(false)
    private val executor = Executors.newFixedThreadPool(2)
    private var tunToGoFuture: Future<*>? = null
    private var goToTunFuture: Future<*>? = null

    fun start() {
        if (!running.compareAndSet(false, true)) {
            Log.w(TAG, "TunDeviceBridge already running")
            return
        }
        Log.d(TAG, "Starting TUN bridge (mtu=$mtu)")

        tunToGoFuture = executor.submit(::tunToGoLoop)
        goToTunFuture = executor.submit(::goToTunLoop)
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        Log.d(TAG, "Stopping TUN bridge")
        // Closing the fd will unblock FileInputStream.read()
        tunFd.close()
        tunToGoFuture?.cancel(true)
        goToTunFuture?.cancel(true)
        executor.shutdownNow()
    }

    // ── TUN → Go ──────────────────────────────────────────────────────────

    private fun tunToGoLoop() {
        val input = FileInputStream(tunFd.fileDescriptor)
        val buffer = ByteArray(mtu + 4) // +4 for tun framing header

        Log.d(TAG, "tunToGoLoop started")
        try {
            while (running.get()) {
                val len = input.read(buffer)
                if (len <= 0) {
                    if (running.get()) Log.w(TAG, "tunToGoLoop: read returned $len")
                    break
                }

                // Determine IP version from first nibble
                val version = (buffer[0].toInt() and 0xF0) shr 4
                val proto = if (version == 6) 6 else 4

                val packet = buffer.copyOf(len)
                goBridge.writePacket(packet, proto)
            }
        } catch (e: Exception) {
            if (running.get()) Log.e(TAG, "tunToGoLoop error: ${e.message}")
        }
        Log.d(TAG, "tunToGoLoop ended")
    }

    // ── Go → TUN ──────────────────────────────────────────────────────────

    private fun goToTunLoop() {
        val output = FileOutputStream(tunFd.fileDescriptor)

        Log.d(TAG, "goToTunLoop started")
        try {
            while (running.get()) {
                val packet = goBridge.readPacket() ?: break
                if (packet.isEmpty()) continue
                output.write(packet)
                output.flush()
            }
        } catch (e: Exception) {
            if (running.get()) Log.e(TAG, "goToTunLoop error: ${e.message}")
        }
        Log.d(TAG, "goToTunLoop ended")
    }
}
