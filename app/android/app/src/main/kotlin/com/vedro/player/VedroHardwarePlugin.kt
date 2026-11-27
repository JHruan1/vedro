package com.vedro.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Rational
import android.view.Display
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Native Android hardware, SAF file picker & external intent bridge for Vedro:
 * - Probes Display HDR capabilities (Dolby Vision, HDR10, HLG, max luminance nits, refresh rate)
 * - Probes MediaCodec hardware decoders (video/dolby-vision, video/hevc, video/av01)
 * - Probes AudioManager IEC61937 bitstream passthrough (TrueHD Atmos, E-AC-3 JOC Atmos, DTS-HD MA) + Spatializer
 * - Native SAF `ACTION_OPEN_DOCUMENT` file picker (`pickFiles`) for local video, subtitles, danmaku XML & fonts
 * - Browser URL launching (`openUrl`) & external Android video player chooser (`launchExternalPlayer`)
 * - Handles Picture-in-Picture (PiP) and WakeLock/KeepScreenOn
 */
class VedroHardwarePlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.vedro.player/hardware"
        private const val REQ_PICK_FILES = 9401

        private val VIDEO_EXTS = setOf(
            "mkv", "mp4", "m4v", "mov", "ts", "m2ts", "webm", "avi", "flv", "wmv", "mpg", "mpeg", "ogm", "iso", "strm"
        )

        fun register(activity: Activity, messenger: BinaryMessenger): VedroHardwarePlugin {
            val channel = MethodChannel(messenger, CHANNEL_NAME)
            val plugin = VedroHardwarePlugin(activity)
            channel.setMethodCallHandler(plugin)
            return plugin
        }

        /**
         * Unlock native high refresh rate (90/120/144Hz) on Android during UI browsing (`fps <= 0f`)
         * and step down to an energy-efficient 60Hz mode during video playback (`fps > 0f`) to
         * prevent unnecessary battery drain and phone heating.
         */
        @Suppress("DEPRECATION")
        fun applyPreferredFrameRate(activity: Activity, fps: Float) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
            activity.runOnUiThread {
                try {
                    val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        activity.display
                    } else {
                        activity.windowManager.defaultDisplay
                    } ?: return@runOnUiThread
                    val current = display.mode ?: return@runOnUiThread
                    val sameResModes = display.supportedModes.filter {
                        it.physicalWidth == current.physicalWidth &&
                            it.physicalHeight == current.physicalHeight
                    }
                    if (sameResModes.isEmpty()) return@runOnUiThread
                    val chosen = if (fps <= 0f) {
                        sameResModes.maxByOrNull { it.refreshRate }
                    } else {
                        sameResModes
                            .filter { it.refreshRate >= fps - 1f }
                            .minByOrNull { it.refreshRate }
                            ?: sameResModes.minByOrNull { kotlin.math.abs(it.refreshRate - fps) }
                    } ?: return@runOnUiThread
                    val lp = activity.window.attributes
                    if (lp.preferredDisplayModeId != chosen.modeId) {
                        lp.preferredDisplayModeId = chosen.modeId
                        activity.window.attributes = lp
                    }
                } catch (_: Throwable) {
                }
            }
        }
    }

    private var pendingPickResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "queryCapabilities" -> result.success(queryCapabilities())
            "enterPiP" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val params = PictureInPictureParams.Builder()
                        .setAspectRatio(Rational(16, 9))
                        .build()
                    activity.enterPictureInPictureMode(params)
                }
                result.success(null)
            }
            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                activity.runOnUiThread {
                    if (enabled) {
                        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
                result.success(null)
            }
            "setPreferredFrameRate" -> {
                val fps = (call.argument<Number>("fps")?.toFloat()) ?: 0f
                applyPreferredFrameRate(activity, fps)
                result.success(null)
            }
            "setWindowChrome" -> {
                val isLight = call.argument<Boolean>("is_light") ?: false
                val canvasArgb = (call.argument<Number>("canvas_argb")?.toLong() ?: 0xFF0B0B0DL).toInt()
                activity.runOnUiThread {
                    val win = activity.window
                    WindowCompat.setDecorFitsSystemWindows(win, false)
                    win.statusBarColor = android.graphics.Color.TRANSPARENT
                    win.navigationBarColor = android.graphics.Color.TRANSPARENT
                    win.decorView.setBackgroundColor(canvasArgb)
                    val ctrl = WindowCompat.getInsetsController(win, win.decorView)
                    ctrl.isAppearanceLightStatusBars = isLight
                    ctrl.isAppearanceLightNavigationBars = isLight
                }
                result.success(null)
            }
            "pickFiles" -> {
                pendingPickResult?.success(emptyList<String>())
                pendingPickResult = result
                val extensions = call.argument<List<String>>("extensions") ?: emptyList()
                val allowMultiple = call.argument<Boolean>("allow_multiple") ?: false
                try {
                    val isVideoOnly = extensions.isNotEmpty() && extensions.all { VIDEO_EXTS.contains(it.lowercase()) }
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (isVideoOnly) "video/*" else "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                    }
                    activity.startActivityForResult(intent, REQ_PICK_FILES)
                } catch (_: Throwable) {
                    pendingPickResult = null
                    result.success(emptyList<String>())
                }
            }
            "openUrl" -> {
                val url = call.argument<String>("url")?.trim() ?: ""
                if (url.isEmpty()) {
                    result.success(false)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity.startActivity(intent)
                    result.success(true)
                } catch (_: Throwable) {
                    result.success(false)
                }
            }
            "launchExternalPlayer" -> {
                val url = call.argument<String>("url")?.trim() ?: ""
                val player = (call.argument<String>("player") ?: "").lowercase()
                val title = call.argument<String>("title") ?: ""
                if (url.isEmpty()) {
                    result.success(false)
                    return
                }
                result.success(launchAndroidExternalPlayer(url, player, title))
            }
            "createVideoSurface" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_FILES) return false
        val pending = pendingPickResult ?: return true
        pendingPickResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(emptyList<String>())
            return true
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        if (uris.isEmpty()) {
            pending.success(emptyList<String>())
            return true
        }
        Thread {
            val pickedDir = File(activity.cacheDir, "picked").apply { mkdirs() }
            try {
                val existing = pickedDir.listFiles()?.sortedBy { it.lastModified() } ?: emptyList()
                if (existing.size > 10) {
                    existing.take(existing.size - 10).forEach { runCatching { it.delete() } }
                }
            } catch (_: Throwable) {}

            val paths = mutableListOf<String>()
            for (uri in uris) {
                try {
                    val rawName = resolveDisplayName(uri) ?: "picked_${System.currentTimeMillis()}"
                    val safeName = rawName.replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5 ()\\[\\]]"), "_")
                    val dest = File(pickedDir, safeName)
                    activity.contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(dest).use { out ->
                            input.copyTo(out, bufferSize = 64 * 1024)
                        }
                    }
                    if (dest.exists() && dest.length() > 0L) {
                        paths.add(dest.absolutePath)
                    }
                } catch (_: Throwable) {}
            }
            activity.runOnUiThread {
                pending.success(paths)
            }
        }.start()
        return true
    }

    private fun resolveDisplayName(uri: Uri): String? {
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val name = c.getString(idx)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        } catch (_: Throwable) {}
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun launchAndroidExternalPlayer(url: String, player: String, title: String): Boolean {
        val uri = Uri.parse(url)
        val packages = when (player) {
            "mxplayer" -> listOf("com.mxtech.videoplayer.pro", "com.mxtech.videoplayer.ad")
            "vlc" -> listOf("org.videolan.vlc")
            "mpv" -> listOf("is.xyz.mpv")
            else -> emptyList()
        }
        for (pkg in packages) {
            try {
                val direct = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "video/*")
                    setPackage(pkg)
                    if (title.isNotBlank()) putExtra("title", title)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(direct)
                return true
            } catch (_: Throwable) {}
        }
        return try {
            val base = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "video/*")
                if (title.isNotBlank()) putExtra("title", title)
            }
            val chooser = Intent.createChooser(base, "选择外部播放器").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(chooser)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun queryCapabilities(): Map<String, Any> {
        var supportsHdr10 = false
        var supportsHlg = false
        var supportsDisplayDolbyVision = false
        var maxLuminance = 1000
        var refreshRate = 60.0

        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }

        if (display != null) {
            refreshRate = display.refreshRate.toDouble()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val hdrCaps = display.hdrCapabilities
                if (hdrCaps != null) {
                    val types = hdrCaps.supportedHdrTypes
                    supportsHdr10 = types.contains(Display.HdrCapabilities.HDR_TYPE_HDR10)
                    supportsHlg = types.contains(Display.HdrCapabilities.HDR_TYPE_HLG)
                    supportsDisplayDolbyVision = types.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)
                    if (hdrCaps.desiredMaxLuminance > 0f) {
                        maxLuminance = hdrCaps.desiredMaxLuminance.toInt()
                    }
                }
            }
        }

        val hasDoviDecoder = hasHardwareCodec("video/dolby-vision")
        val hasHevc10Decoder = hasHardwareCodec("video/hevc")
        val hasAv1Decoder = hasHardwareCodec("video/av01")

        val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        var supportsTrueHdAtmos = false
        var supportsEac3JocAtmos = false
        var supportsDtsHd = false
        var supportsSpatializer = false

        if (audioManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (dev in outputs) {
                val encodings = dev.encodings
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    if (encodings.contains(AudioFormat.ENCODING_DOLBY_TRUEHD)) supportsTrueHdAtmos = true
                    if (encodings.contains(AudioFormat.ENCODING_E_AC3_JOC)) supportsEac3JocAtmos = true
                }
                if (encodings.contains(AudioFormat.ENCODING_DTS_HD)) supportsDtsHd = true
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S_V2) {
                supportsSpatializer = audioManager.spatializer.isAvailable
            }
        }

        val systemProxyUrl = detectAndroidProxyUrl()

        return mapOf(
            "supports_hdr10" to supportsHdr10,
            "supports_hlg" to supportsHlg,
            "supports_native_dolby_vision" to (supportsDisplayDolbyVision && hasDoviDecoder),
            "has_hevc_hwdec" to hasHevc10Decoder,
            "has_av1_hwdec" to hasAv1Decoder,
            "supports_atmos_bitstream" to (supportsTrueHdAtmos || supportsEac3JocAtmos),
            "supports_truehd_atmos" to supportsTrueHdAtmos,
            "supports_eac3_joc_atmos" to supportsEac3JocAtmos,
            "supports_dts_hd" to supportsDtsHd,
            "supports_spatial_audio" to supportsSpatializer,
            "max_luminance_nits" to maxLuminance,
            "refresh_rate_hz" to refreshRate,
            "system_proxy_url" to (systemProxyUrl ?: "")
        )
    }

    private fun detectAndroidProxyUrl(): String? {
        try {
            val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val proxy = cm.defaultProxy
                if (proxy != null && !proxy.host.isNullOrBlank() && proxy.port > 0) {
                    return "http://${proxy.host}:${proxy.port}"
                }
            }
        } catch (_: Throwable) {}
        val host = System.getProperty("http.proxyHost") ?: System.getProperty("https.proxyHost")
        val port = System.getProperty("http.proxyPort") ?: System.getProperty("https.proxyPort")
        if (!host.isNullOrBlank() && !port.isNullOrBlank()) {
            return "http://$host:$port"
        }
        return null
    }

    private fun hasHardwareCodec(mime: String): Boolean {
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        return list.codecInfos.any { info ->
            !info.isEncoder &&
                info.supportedTypes.any { it.equals(mime, ignoreCase = true) } &&
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.isHardwareAccelerated else !info.name.startsWith("OMX.google."))
        }
    }
}
