package com.vedro.player

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecList
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
        private const val ACTION_PIP_TOGGLE_PLAY = "com.vedro.player.PIP_TOGGLE_PLAY"
        private const val MAX_CACHE_COPY_BYTES = 32L * 1024L * 1024L

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
    private var pipReceiverRegistered = false
    private var audioFocusRequest: Any? = null
    private var mediaSession: MediaSession? = null
    private var autoPipEnabled = false
    private var pipAspectW = 16
    private var pipAspectH = 9
    private var nowPlayingActive = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                emitAudioInterrupted("becoming_noisy")
            }
        }
    }

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PIP_TOGGLE_PLAY) {
                emitMediaAction("toggle_play")
            }
        }
    }

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> emitAudioInterrupted("focus_loss")
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> emitMediaAction("duck")
            AudioManager.AUDIOFOCUS_GAIN -> emitMediaAction("unduck")
        }
    }

    private fun emitAudioInterrupted(reason: String) {
        activity.runOnUiThread {
            try {
                channel.invokeMethod("audioInterrupted", mapOf("reason" to reason))
            } catch (_: Throwable) {}
        }
    }

    private fun emitMediaAction(action: String, extra: Map<String, Any>? = null) {
        activity.runOnUiThread {
            try {
                val payload = mutableMapOf<String, Any>("action" to action)
                if (extra != null) payload.putAll(extra)
                channel.invokeMethod("mediaAction", payload)
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

    fun onUserLeaveHint() {
        if (!autoPipEnabled || !nowPlayingActive) return
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            enterPipInternal(pipAspectW, pipAspectH, playing = true)
        }
    }

    fun cleanup() {
        setAudioPlaybackActive(false)
        releaseMediaSession()
        unregisterPipReceiver()
        pendingPickResult?.success(emptyList<String>())
        pendingPickResult = null
    }

    private fun ensureMediaSession() {
        if (mediaSession != null) return
        try {
            val session = MediaSession(activity, "VedroMediaSession")
            session.setCallback(object : MediaSession.Callback() {
                override fun onPlay() = emitMediaAction("play")
                override fun onPause() = emitMediaAction("pause")
                override fun onSkipToNext() = emitMediaAction("next")
                override fun onSkipToPrevious() = emitMediaAction("previous")
                override fun onStop() = emitMediaAction("pause")
                override fun onSeekTo(pos: Long) = emitMediaAction("seek", mapOf("position_ms" to pos))
            })
            session.isActive = true
            mediaSession = session
        } catch (_: Throwable) {}
    }

    private fun releaseMediaSession() {
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
        } catch (_: Throwable) {}
        mediaSession = null
        nowPlayingActive = false
    }

    private fun updateNowPlaying(
        title: String,
        subtitle: String,
        durationMs: Long,
        positionMs: Long,
        isPlaying: Boolean,
        speed: Float,
        hasNext: Boolean,
        hasPrevious: Boolean,
        active: Boolean
    ) {
        if (!active || (title.isBlank() && !isPlaying)) {
            releaseMediaSession()
            updatePipParamsIfSupported(false)
            return
        }
        nowPlayingActive = isPlaying
        ensureMediaSession()
        val session = mediaSession ?: return
        try {
            val meta = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs.coerceAtLeast(0L))
                .build()
            session.setMetadata(meta)
            var actions = PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_SEEK_TO
            if (hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
            if (hasPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
            val state = PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    positionMs.coerceAtLeast(0L),
                    if (isPlaying) speed.coerceIn(0.25f, 4.0f) else 0f
                )
                .build()
            session.setPlaybackState(state)
            updatePipParamsIfSupported(isPlaying)
        } catch (_: Throwable) {}
    }

    private fun ensurePipReceiver() {
        if (pipReceiverRegistered) return
        try {
            val filter = IntentFilter(ACTION_PIP_TOGGLE_PLAY)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(pipActionReceiver, filter)
            }
            pipReceiverRegistered = true
        } catch (_: Throwable) {}
    }

    private fun unregisterPipReceiver() {
        if (!pipReceiverRegistered) return
        try {
            activity.unregisterReceiver(pipActionReceiver)
        } catch (_: Throwable) {}
        pipReceiverRegistered = false
    }

    private fun buildPipParams(aw: Int, ah: Int, playing: Boolean): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val ratio = (aw.coerceAtLeast(1).toDouble() / ah.coerceAtLeast(1).toDouble()).coerceIn(0.45, 2.35)
        val rational = Rational((ratio * 100).toInt().coerceAtLeast(45), 100)
        ensurePipReceiver()
        val intent = Intent(ACTION_PIP_TOGGLE_PLAY).setPackage(activity.packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pending = PendingIntent.getBroadcast(activity, 1, intent, flags)
        val iconRes = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val label = if (playing) "暂停" else "播放"
        val action = RemoteAction(Icon.createWithResource(activity, iconRes), label, label, pending)
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(rational)
            .setActions(listOf(action))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPipEnabled && playing)
        }
        return builder.build()
    }

    private fun updatePipParamsIfSupported(playing: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            activity.runOnUiThread {
                try {
                    buildPipParams(pipAspectW, pipAspectH, playing)?.let {
                        activity.setPictureInPictureParams(it)
                    }
                } catch (_: Throwable) {}
            }
        }
    }

    private fun enterPipInternal(aw: Int, ah: Int, playing: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            return false
        }
        pipAspectW = aw.coerceAtLeast(1)
        pipAspectH = ah.coerceAtLeast(1)
        return try {
            val params = buildPipParams(pipAspectW, pipAspectH, playing) ?: return false
            activity.enterPictureInPictureMode(params)
        } catch (_: Throwable) {
            false
        }
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
                        // Abandon any prior AudioFocusRequest so repeated calls never leak focus handles
                        (audioFocusRequest as? AudioFocusRequest)?.let { am.abandonAudioFocusRequest(it) }
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
            releaseMediaSession()
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
            "updateNowPlaying" -> {
                val title = call.argument<String>("title") ?: ""
                val subtitle = call.argument<String>("subtitle") ?: ""
                val durationMs = call.argument<Number>("duration_ms")?.toLong()
                    ?: ((call.argument<Number>("duration_secs")?.toDouble() ?: 0.0) * 1000.0).toLong()
                val positionMs = call.argument<Number>("position_ms")?.toLong()
                    ?: ((call.argument<Number>("position_secs")?.toDouble() ?: 0.0) * 1000.0).toLong()
                val isPlaying = call.argument<Boolean>("is_playing")
                    ?: call.argument<Boolean>("playing")
                    ?: false
                val speed = (call.argument<Number>("speed")?.toFloat()) ?: 1.0f
                val hasNext = call.argument<Boolean>("has_next") ?: false
                val hasPrevious = call.argument<Boolean>("has_previous") ?: false
                val active = call.argument<Boolean>("active") ?: true
                updateNowPlaying(title, subtitle, durationMs, positionMs, isPlaying, speed, hasNext, hasPrevious, active)
                result.success(null)
            }
            "setAutoPipEnabled" -> {
                autoPipEnabled = call.argument<Boolean>("enabled") ?: false
                pipAspectW = (call.argument<Number>("aspect_w")?.toInt() ?: pipAspectW).coerceAtLeast(1)
                pipAspectH = (call.argument<Number>("aspect_h")?.toInt() ?: pipAspectH).coerceAtLeast(1)
                updatePipParamsIfSupported(nowPlayingActive)
                result.success(null)
            }
            "saveScreenshotToGallery" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = (call.argument<String>("file_name") ?: "vedro_${System.currentTimeMillis()}.png")
                    .replace(Regex("[^A-Za-z0-9._\\-]"), "_")
                if (bytes == null || bytes.isEmpty()) {
                    result.success(null)
                    return
                }
                Thread {
                    val savedPath = savePngToAndroidGallery(bytes, fileName)
                    activity.runOnUiThread {
                        if (!activity.isFinishing && !activity.isDestroyed) {
                            runCatching { result.success(savedPath) }
                        }
                    }
                }.start()
            }
            "getScreenBrightness" -> {
                var value = activity.window.attributes.screenBrightness
                if (value < 0f) {
                    val sys = runCatching {
                        Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                    }.getOrDefault(128)
                    val maxBright = resolveMaxSystemBrightness(sys)
                    value = (sys.toFloat() / maxBright.toFloat()).coerceIn(0.05f, 1.0f)
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
                val aw = (call.argument<Number>("aspect_w")?.toInt() ?: 16).coerceAtLeast(1)
                val ah = (call.argument<Number>("aspect_h")?.toInt() ?: 9).coerceAtLeast(1)
                result.success(enterPipInternal(aw, ah, playing = true))
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
                    if (Build.VERSION.SDK_INT < 35) {
                        @Suppress("DEPRECATION")
                        win.statusBarColor = android.graphics.Color.TRANSPARENT
                        @Suppress("DEPRECATION")
                        win.navigationBarColor = android.graphics.Color.TRANSPARENT
                    }
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
                    val fileSize = resolveFileSize(appCtx, uri)
                    // Never copy multi-GB local movies into cacheDir! Pass direct filesystem path
                    // (when resolvable) or content:// URI directly to libmpv/media_kit.
                    if (fileSize < 0L || fileSize > MAX_CACHE_COPY_BYTES) {
                        runCatching {
                            appCtx.contentResolver.takePersistableUriPermission(
                                uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                        }
                        val directPath = resolveDirectStoragePath(uri)
                        paths.add(directPath ?: uri.toString())
                        continue
                    }
                    val rawName = resolveDisplayName(appCtx, uri) ?: "picked_${System.currentTimeMillis()}"
                    val safeName = rawName
                        .replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5 ()\\[\\]]"), "_")
                        .trimStart('.')
                        .ifEmpty { "picked_${System.currentTimeMillis()}" }
                    val uniqueName = "${System.currentTimeMillis() % 100000}_$safeName"
                    val dest = File(pickedDir, uniqueName)
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
            activity.runOnUiThread {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    runCatching { pending.success(paths) }
                }
            }
        }.start()
        return true
    }

    private fun resolveMaxSystemBrightness(currentVal: Int): Int {
        val resId = activity.resources.getIdentifier(
            "config_screenBrightnessSettingMaximum",
            "integer",
            "android"
        )
        val oemMax = if (resId != 0) runCatching { activity.resources.getInteger(resId) }.getOrDefault(255) else 255
        var maxV = oemMax.coerceAtLeast(255)
        if (currentVal > maxV) {
            maxV = when {
                currentVal <= 1023 -> 1023
                currentVal <= 2047 -> 2047
                currentVal <= 4095 -> 4095
                else -> 16383
            }
        }
        return maxV
    }

    private fun resolveFileSize(ctx: Context, uri: Uri): Long {
        try {
            ctx.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.SIZE)
                    if (idx >= 0 && !c.isNull(idx)) {
                        return c.getLong(idx)
                    }
                }
            }
        } catch (_: Throwable) {}
        return -1L
    }

    private fun resolveDirectStoragePath(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        val docId = uri.lastPathSegment ?: return null
        if (uri.authority == "com.android.externalstorage.documents" && docId.startsWith("primary:")) {
            val rel = docId.removePrefix("primary:")
            val candidate = File(Environment.getExternalStorageDirectory(), rel)
            if (candidate.exists() && candidate.canRead()) {
                return candidate.absolutePath
            }
        }
        return null
    }

    private fun savePngToAndroidGallery(bytes: ByteArray, fileName: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Vedro")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val resolver = activity.applicationContext.contentResolver
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                "Pictures/Vedro/$fileName"
            } else {
                @Suppress("DEPRECATION")
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Vedro")
                dir.mkdirs()
                val out = File(dir, fileName)
                FileOutputStream(out).use { it.write(bytes) }
                out.absolutePath
            }
        } catch (_: Throwable) {
            null
        }
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
        return pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature("android.hardware.type.television") ||
            pm.hasSystemFeature("amazon.hardware.fire_tv")
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
