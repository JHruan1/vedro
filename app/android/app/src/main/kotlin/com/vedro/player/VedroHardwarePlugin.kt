package com.vedro.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
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
 * Native Android & Android TV hardware bridge for Vedro:
 * - Android TV / Leanback / Touchscreen detection (`is_tv`, `has_touchscreen`, `supports_pip`)
 * - Audio Focus & `ACTION_AUDIO_BECOMING_NOISY` (auto-pause when headphones/BT unplug or call arrives)
 * - Real OS window screen brightness (`getScreenBrightness`, `setScreenBrightness`, `resetScreenBrightness`)
 * - Battery level & charging state (`getBatteryInfo`) and Wi-Fi / unmetered check (`isWifiConnected`)
 * - Safe PiP with dynamic video aspect ratio + `pipModeChanged` callback
 * - Display HDR / MediaCodec / IEC61937 Atmos probing, SAF file picker & validated HTTP/HTTPS intents
 */
class VedroHardwarePlugin(
    private val activity: Activity,
    private val channel: MethodChannel
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.vedro.player/hardware"
        private const val REQ_PICK_FILES = 9401

        private val VIDEO_EXTS = setOf(
            "mkv", "mp4", "m4v", "mov", "ts", "m2ts", "webm", "avi", "flv", "wmv", "mpg", "mpeg", "ogm", "iso", "strm"
        )

        fun register(activity: Activity, messenger: BinaryMessenger): VedroHardwarePlugin {
            val channel = MethodChannel(messenger, CHANNEL_NAME)
            val plugin = VedroHardwarePlugin(activity, channel)
            channel.setMethodCallHandler(plugin)
            return plugin
        }

        private fun isAllowedHttpUrl(raw: String): Boolean {
            val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return false
            val scheme = uri.scheme?.lowercase() ?: return false
            return (scheme == "http" || scheme == "https") && !uri.host.isNullOrBlank()
        }

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
    private var noisyReceiverRegistered = false
    private var audioFocusRequest: Any? = null

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                emitAudioInterrupted("becoming_noisy")
            }
        }
    }

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> emitAudioInterrupted("focus_loss")
        }
    }

    private fun emitAudioInterrupted(reason: String) {
        activity.runOnUiThread {
            try {
                channel.invokeMethod("audioInterrupted", mapOf("reason" to reason))
            } catch (_: Throwable) {}
        }
    }

    fun notifyPipModeChanged(inPip: Boolean) {
        activity.runOnUiThread {
            try {
                channel.invokeMethod("pipModeChanged", mapOf("in_pip" to inPip))
            } catch (_: Throwable) {}
        }
    }

    fun cleanup() {
        setAudioPlaybackActive(false)
        pendingPickResult?.success(emptyList<String>())
        pendingPickResult = null
    }

    @Suppress("DEPRECATION")
    private fun setAudioPlaybackActive(active: Boolean) {
        val am = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (active) {
            if (!noisyReceiverRegistered) {
                try {
                    val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        activity.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        activity.registerReceiver(noisyReceiver, filter)
                    }
                    noisyReceiverRegistered = true
                } catch (_: Throwable) {}
            }
            if (am != null) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                            .setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                    .build()
                            )
                            .setAcceptsDelayedFocusGain(false)
                            .setOnAudioFocusChangeListener(audioFocusListener)
                            .build()
                        audioFocusRequest = req
                        am.requestAudioFocus(req)
                    } else {
                        am.requestAudioFocus(
                            audioFocusListener,
                            AudioManager.STREAM_MUSIC,
                            AudioManager.AUDIOFOCUS_GAIN
                        )
                    }
                } catch (_: Throwable) {}
            }
        } else {
            if (noisyReceiverRegistered) {
                try {
                    activity.unregisterReceiver(noisyReceiver)
                } catch (_: Throwable) {}
                noisyReceiverRegistered = false
            }
            if (am != null) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        (audioFocusRequest as? AudioFocusRequest)?.let { am.abandonAudioFocusRequest(it) }
                        audioFocusRequest = null
                    } else {
                        am.abandonAudioFocus(audioFocusListener)
                    }
                } catch (_: Throwable) {}
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "queryCapabilities" -> result.success(queryCapabilities())
            "setAudioPlaybackActive" -> {
                val active = call.argument<Boolean>("active") ?: false
                setAudioPlaybackActive(active)
                result.success(null)
            }
            "getScreenBrightness" -> {
                var value = activity.window.attributes.screenBrightness
                if (value < 0f) {
                    val sys = runCatching {
                        Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                    }.getOrDefault(128)
                    value = (sys / 255f).coerceIn(0.05f, 1.0f)
                }
                result.success(value.toDouble())
            }
            "setScreenBrightness" -> {
                val v = (call.argument<Number>("value")?.toFloat() ?: 0.5f).coerceIn(0.01f, 1.0f)
                activity.runOnUiThread {
                    try {
                        val lp = activity.window.attributes
                        lp.screenBrightness = v
                        activity.window.attributes = lp
                    } catch (_: Throwable) {}
                }
                result.success(null)
            }
            "resetScreenBrightness" -> {
                activity.runOnUiThread {
                    try {
                        val lp = activity.window.attributes
                        lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        activity.window.attributes = lp
                    } catch (_: Throwable) {}
                }
                result.success(null)
            }
            "getBatteryInfo" -> {
                val intent = runCatching {
                    activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                }.getOrNull()
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
                val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val pct = if (level >= 0 && scale > 0) ((level * 100) / scale).coerceIn(0, 100) else -1
                val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
                result.success(mapOf("level" to pct, "charging" to charging))
            }
            "isWifiConnected" -> {
                result.success(isUnmeteredOrWifi())
            }
            "enterPiP" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                ) {
                    val aw = (call.argument<Number>("aspect_w")?.toInt() ?: 16).coerceAtLeast(1)
                    val ah = (call.argument<Number>("aspect_h")?.toInt() ?: 9).coerceAtLeast(1)
                    // Clamp ratio to Android's strict PiP bounds [0.4184, 2.39] to prevent IllegalArgumentException
                    val ratio = (aw.toDouble() / ah.toDouble()).coerceIn(0.45, 2.35)
                    val rational = Rational((ratio * 100).toInt().coerceAtLeast(45), 100)
                    val ok = try {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(rational)
                            .build()
                        activity.enterPictureInPictureMode(params)
                    } catch (_: Throwable) {
                        false
                    }
                    result.success(ok)
                } else {
                    result.success(false)
                }
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
                if (!isAllowedHttpUrl(url)) {
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
                if (!isAllowedHttpUrl(url)) {
                    result.success(false)
                    return
                }
                result.success(launchAndroidExternalPlayer(url, player, title))
            }
            "createVideoSurface" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun isUnmeteredOrWifi(): Boolean {
        return try {
            val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val net = cm.activeNetwork ?: return false
                val caps = cm.getNetworkCapabilities(net) ?: return false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            } else {
                !cm.isActiveNetworkMetered
            }
        } catch (_: Throwable) {
            true
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
        val appCtx = activity.applicationContext
        Thread {
            val pickedDir = File(appCtx.cacheDir, "picked").apply { mkdirs() }
            try {
                val existing = pickedDir.listFiles()?.sortedBy { it.lastModified() } ?: emptyList()
                if (existing.size > 6) {
                    existing.take(existing.size - 6).forEach { runCatching { it.delete() } }
                }
            } catch (_: Throwable) {}

            val paths = mutableListOf<String>()
            for (uri in uris) {
                try {
                    val rawName = resolveDisplayName(appCtx, uri) ?: "picked_${System.currentTimeMillis()}"
                    val safeName = rawName
                        .replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5 ()\\[\\]]"), "_")
                        .trimStart('.')
                        .ifEmpty { "picked_${System.currentTimeMillis()}" }
                    val dest = File(pickedDir, safeName)
                    appCtx.contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(dest).use { out ->
                            input.copyTo(out, bufferSize = 64 * 1024)
                        }
                    }
                    if (dest.exists() && dest.length() > 0L) {
                        paths.add(dest.absolutePath)
                    }
                } catch (_: Throwable) {}
            }
            if (!activity.isFinishing && !activity.isDestroyed) {
                activity.runOnUiThread {
                    pending.success(paths)
                }
            }
        }.start()
        return true
    }

    private fun resolveDisplayName(ctx: Context, uri: Uri): String? {
        try {
            ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
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

    private fun isAndroidTvDevice(): Boolean {
        val uiMode = activity.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        val pm = activity.packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature("android.hardware.type.television")
        ) {
            return true
        }
        return !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
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

        val isTv = isAndroidTvDevice()
        val hasTouchscreen = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        val supportsPip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        val systemProxyUrl = detectAndroidProxyUrl()

        return mapOf(
            "is_tv" to isTv,
            "has_touchscreen" to hasTouchscreen,
            "supports_pip" to supportsPip,
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
