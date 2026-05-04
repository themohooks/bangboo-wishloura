package com.example.fluttervpngo.vpnplugin

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * Helpers for managing the VPN app-exclusion (split-tunnel) list.
 * Mirrors the ExceptionsTab logic from proxy-turn-vk-android.
 */
object AppExclusionsHelper {

    data class AppInfo(
        val packageName: String,
        val label: String,
        val iconBase64: String,   // PNG, base64-encoded for Flutter platform channel
    )

    /**
     * Returns all installed apps that have a launcher intent
     * (i.e., user-visible apps), sorted by label.
     */
    fun getInstalledApps(context: Context): List<AppInfo> {
        val pm = context.packageManager
        val intent = android.content.Intent(android.content.Intent.ACTION_MAIN, null).apply {
            addCategory(android.content.Intent.CATEGORY_LAUNCHER)
        }
        return pm.queryIntentActivities(intent, PackageManager.GET_META_DATA)
            .mapNotNull { ri ->
                runCatching {
                    val pkg = ri.activityInfo.packageName
                    val label = ri.loadLabel(pm).toString()
                    val icon = ri.loadIcon(pm)
                    AppInfo(pkg, label, drawableToBase64(icon))
                }.getOrNull()
            }
            .sortedBy { it.label.lowercase() }
    }

    /**
     * Converts a Drawable to a base64-encoded PNG string for transmission
     * over the Flutter platform channel.
     */
    private fun drawableToBase64(drawable: Drawable): String {
        val bitmap = when (drawable) {
            is BitmapDrawable -> drawable.bitmap
            else -> {
                val bmp = Bitmap.createBitmap(
                    drawable.intrinsicWidth.coerceAtLeast(48),
                    drawable.intrinsicHeight.coerceAtLeast(48),
                    Bitmap.Config.ARGB_8888,
                )
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }

    /**
     * Persist excluded package list to SharedPreferences (simple storage,
     * no DataStore dependency on the plugin module).
     */
    fun saveExclusions(context: Context, packages: Set<String>) {
        context.getSharedPreferences("vpn_prefs", Context.MODE_PRIVATE)
            .edit()
            .putStringSet("excluded_apps", packages)
            .apply()
    }

    fun loadExclusions(context: Context): Set<String> =
        context.getSharedPreferences("vpn_prefs", Context.MODE_PRIVATE)
            .getStringSet("excluded_apps", emptySet()) ?: emptySet()

    fun saveIsWhitelist(context: Context, isWhitelist: Boolean) {
        context.getSharedPreferences("vpn_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean("is_whitelist", isWhitelist).apply()
    }

    fun loadIsWhitelist(context: Context): Boolean =
        context.getSharedPreferences("vpn_prefs", Context.MODE_PRIVATE)
            .getBoolean("is_whitelist", false)
}
