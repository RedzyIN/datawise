package com.datawise.datawise

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
                result.success(
                    openSettings(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), null)
                )
            }
            "openInternetSettings" -> result.success(openInternetSettings())
            "getMobileUsage" -> {
                val start = call.argument<Number>("startMillis")?.toLong() ?: 0L
                val end = call.argument<Number>("endMillis")?.toLong() ?: 0L
                // Kerja berat di thread lain, jawaban dikirim balik di thread utama
                executor.execute {
                    val map = readUsage(start, end)
                    main.post { result.success(map) }
                }
            }
            "getMobileUsageByApp" -> {
                val start = call.argument<Number>("startMillis")?.toLong() ?: 0L
                val end = call.argument<Number>("endMillis")?.toLong() ?: 0L
                executor.execute {
                    val map = readAppUsage(start, end)
                    main.post { result.success(map) }
                }
            }
            "getAppIcons" -> {
                val names = call.argument<List<String>>("packageNames") ?: emptyList()
                executor.execute {
                    val map = readIcons(names)
                    main.post { result.success(map) }
                }
            }
            else -> result.notImplemented()
        }
    }

    // Perpanjangan ujung query agar bucket berjalan (belum utuh) ikut terbaca.
    // Panjang bucket NetworkStats berada di kisaran jam, jadi 6 jam cukup
    // untuk semua varian perangkat tanpa menarik data masa depan.
    private val ONGOING_BUCKET_GRACE_MS = 6L * 60 * 60 * 1000

    // Cache UID -> identitas aplikasi karena queryDetails menghasilkan banyak
    // bucket untuk UID yang sama.
    private val uidInfoCache = HashMap<Int, UidInfo>()

    private data class UidInfo(val packageName: String?, val appName: String)

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

    // Rincian per UID aplikasi. Bucket dengan UID dan rentang waktu sama
    // digabung agar state foreground/background tidak dihitung dua kali.
    private fun readAppUsage(start: Long, end: Long): Map<String, Any?> {
        fun out(status: String, apps: List<Map<String, Any?>>, msg: String?) = mapOf(
            "status" to status, "apps" to apps,
            "startMillis" to start, "endMillis" to end, "message" to msg
        )
        if (end <= start) return out("error", emptyList(), "Rentang waktu tidak valid.")
        if (!hasPermission()) return out("permission_denied", emptyList(), "Izin akses penggunaan belum diberikan.")
        return try {
            val nsm = context.getSystemService(Context.NETWORK_STATS_SERVICE) as? NetworkStatsManager
                ?: return out("unsupported", emptyList(), "Perangkat tidak mendukung statistik data.")
            // queryDetails hanya mengembalikan bucket yang seluruh rentangnya
            // berada di dalam [start, end] ("only includes buckets that
            // atomically occur in the inclusive time range"). Akibatnya bucket
            // yang masih berjalan - tempat pemakaian terbaru - tidak pernah
            // ikut, sehingga angka aplikasi baru bertambah setelah bucket
            // selesai. Ujung query diperpanjang melewati batas bucket agar
            // bucket berjalan tetap terbaca; data setelah `end` belum ada dan
            // tetap dipotong ke waktu sekarang saat disimpan.
            val queryEnd = end + ONGOING_BUCKET_GRACE_MS
            val stats = nsm.queryDetails(
                ConnectivityManager.TYPE_MOBILE, null, start, queryEnd
            )
            val aggregated = LinkedHashMap<String, MutableMap<String, Any?>>()
            try {
                val bucket = NetworkStats.Bucket()
                while (stats.hasNextBucket()) {
                    stats.getNextBucket(bucket)
                    if (bucket.uid < 0) continue
                    val key = "${bucket.uid}|${bucket.startTimeStamp}|${bucket.endTimeStamp}"
                    val existing = aggregated[key]
                    if (existing == null) {
                        val uidInfo = resolveUid(bucket.uid)
                        aggregated[key] = mutableMapOf(
                            "uid" to bucket.uid,
                            "packageName" to uidInfo.packageName,
                            "appName" to uidInfo.appName,
                            "rxBytes" to bucket.rxBytes,
                            "txBytes" to bucket.txBytes,
                            "bucketStartMillis" to bucket.startTimeStamp,
                            "bucketEndMillis" to bucket.endTimeStamp
                        )
                    } else {
                        existing["rxBytes"] = (existing["rxBytes"] as Long) + bucket.rxBytes
                        existing["txBytes"] = (existing["txBytes"] as Long) + bucket.txBytes
                    }
                }
            } finally {
                stats.close()
            }
            out("ok", aggregated.values.toList(), null)
        } catch (e: SecurityException) {
            out("permission_denied", emptyList(), "Izin ditolak sistem.")
        } catch (e: Exception) {
            out("error", emptyList(), e.message ?: "Gagal membaca statistik aplikasi.")
        }
    }

    // Ukuran ikon yang dikirim ke Flutter. Cukup tajam untuk kartu 40dp pada
    // layar kerapatan tinggi tanpa membengkakkan payload MethodChannel.
    private val ICON_SIZE_PX = 128

    // Cache ikon per package name: PackageManager dan encode PNG hanya dilakukan
    // sekali per aplikasi selama proses hidup, sehingga membuka daftar berulang
    // tidak mengambil ikon yang sama terus-menerus.
    private val iconCache = HashMap<String, String>()

    // Launcher icon asli per package name. Package yang tidak terlihat karena
    // batas package visibility Android 11+ tidak menghasilkan entri sehingga
    // Flutter memakai ikon fallback DATAWISE. Tidak ada QUERY_ALL_PACKAGES.
    private fun readIcons(packageNames: List<String>): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        val pm = context.packageManager

        for (name in packageNames) {
            if (name.isBlank()) continue

            synchronized(iconCache) { iconCache[name] }?.let {
                out[name] = it
                continue
            }

            val encoded = try {
                encodeIcon(pm.getApplicationIcon(name))
            } catch (_: Exception) {
                null
            }

            if (encoded != null) {
                synchronized(iconCache) { iconCache[name] = encoded }
                out[name] = encoded
            }
        }

        return out
    }

    private fun encodeIcon(drawable: Drawable): String {
        val bitmap = drawableToBitmap(drawable)
        val scaled = if (bitmap.width == ICON_SIZE_PX && bitmap.height == ICON_SIZE_PX) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, ICON_SIZE_PX, ICON_SIZE_PX, true)
        }

        val stream = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.PNG, 100, stream)

        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        val bitmapDrawable = drawable as? BitmapDrawable
        if (bitmapDrawable?.bitmap != null) return bitmapDrawable.bitmap

        val bitmap = Bitmap.createBitmap(
            ICON_SIZE_PX, ICON_SIZE_PX, Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)

        return bitmap
    }

    // Pemetaan UID ke aplikasi. Android 11+ membatasi package visibility, jadi
    // <queries> MAIN/LAUNCHER di manifest membuat aplikasi ber-launcher terlihat
    // dan labelnya terbaca. UID sistem tanpa paket memakai label tetap supaya
    // tidak tampil sebagai "uid-xxxx".
    private fun resolveUid(uid: Int): UidInfo = synchronized(uidInfoCache) {
        uidInfoCache.getOrPut(uid) { lookupUid(uid) }
    }

    private fun lookupUid(uid: Int): UidInfo {
        val pm = context.packageManager
        val packages = try {
            pm.getPackagesForUid(uid)?.sorted().orEmpty()
        } catch (_: Exception) {
            emptyList()
        }

        // Satu UID bisa dipakai beberapa paket (mis. layanan Google). Utamakan
        // paket yang punya launcher karena itulah yang dikenal pengguna.
        val preferred = packages.firstOrNull { name ->
            try {
                pm.getLaunchIntentForPackage(name) != null
            } catch (_: Exception) {
                false
            }
        } ?: packages.firstOrNull()

        if (preferred != null) {
            val label = try {
                val appInfo = pm.getApplicationInfo(preferred, 0)
                pm.getApplicationLabel(appInfo).toString().trim()
            } catch (_: Exception) {
                ""
            }
            return UidInfo(preferred, label.ifEmpty { preferred })
        }

        return UidInfo(null, systemUidLabel(uid))
    }

    private fun systemUidLabel(uid: Int): String = when (uid) {
        0 -> "Root"
        1000 -> "Sistem Android"
        1001 -> "Radio"
        1002 -> "Bluetooth"
        1010 -> "Wi-Fi"
        1013 -> "Media"
        1016 -> "VPN"
        1073 -> "Network Stack"
        2000 -> "Shell"
        else -> if (uid < 10000) {
            "Layanan sistem (UID $uid)"
        } else {
            "Aplikasi tidak dikenal (UID $uid)"
        }
    }

    // Membuka halaman pengaturan tanpa mengubah jaringan apa pun. Hasil Boolean
    // dikirim ke Flutter supaya UI bisa menampilkan pesan gagal, bukan diam-diam.
    // minSdk 29 sehingga panel internet selalu tersedia, fallback tetap dipakai
    // untuk perangkat/OEM yang menonaktifkan panel tersebut.
    private fun openInternetSettings(): Boolean {
        if (
            openSettings(
                Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY),
                Intent(Settings.ACTION_WIRELESS_SETTINGS)
            )
        ) {
            return true
        }

        return openSettings(Intent(Settings.ACTION_SETTINGS), null)
    }

    private fun openSettings(primary: Intent, fallback: Intent?): Boolean {
        try {
            primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(primary)
            return true
        } catch (_: Exception) {
            if (fallback == null) return false

            return try {
                fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(fallback)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
