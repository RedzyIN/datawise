package com.datawise.datawise

import android.app.AppOpsManager
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// PEMILIK: Anggota C. KONTRAK BEKU #5 - channel 'datawise/usage'.
class UsageChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "datawise/usage").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasUsagePermission" -> result.success(hasPermission())
            "openUsageAccessSettings" -> {
                openSettings(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), null)
                result.success(null)
            }
            "openInternetSettings" -> {
                openSettings(
                    Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY),
                    Intent(Settings.ACTION_WIRELESS_SETTINGS)
                )
                result.success(null)
            }
            "getMobileUsage" -> {
                val start = call.argument<Number>("startMillis")?.toLong() ?: 0L
                val end = call.argument<Number>("endMillis")?.toLong() ?: 0L
                // Kerja berat di thread lain, jawaban dikirim balik di thread utama
                executor.execute {
                    val map = readUsage(start, end)
                    main.post { result.success(map) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun readUsage(start: Long, end: Long): Map<String, Any?> {
        fun out(status: String, total: Long, msg: String?) = mapOf(
            "status" to status, "totalBytes" to total,
            "startMillis" to start, "endMillis" to end, "message" to msg
        )
        if (end <= start) return out("error", 0L, "Rentang waktu tidak valid.")
        if (!hasPermission()) return out("permission_denied", 0L, "Izin akses penggunaan belum diberikan.")
        return try {
            val nsm = context.getSystemService(Context.NETWORK_STATS_SERVICE) as? NetworkStatsManager
                ?: return out("unsupported", 0L, "Perangkat tidak mendukung statistik data.")
            // subscriberId null = gabungan semua SIM data seluler (Android 10+)
            val b = nsm.querySummaryForDevice(ConnectivityManager.TYPE_MOBILE, null, start, end)
            out("ok", b.rxBytes + b.txBytes, null)
        } catch (e: SecurityException) {
            out("permission_denied", 0L, "Izin ditolak sistem.")
        } catch (e: Exception) {
            out("error", 0L, e.message ?: "Gagal membaca statistik.")
        }
    }

    private fun openSettings(primary: Intent, fallback: Intent?) {
        try {
            primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(primary)
        } catch (e: Exception) {
            if (fallback != null) {
                try {
                    fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(fallback)
                } catch (_: Exception) { }
            }
        }
    }
}
