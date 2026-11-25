package com.vedro.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.os.Build
import android.util.Rational
import android.view.Display
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android hardware bridge for Vedro:
 * - Probes Display HDR capabilities (Dolby Vision, HDR10, HDR10+, HLG, max luminance nits, refresh rate)
 * - Probes MediaCodec hardware decoders (video/dolby-vision, video/hevc, video/av01)
 * - Probes AudioManager IEC61937 bitstream passthrough (TrueHD Atmos, E-AC-3 JOC Atmos, DTS-HD MA) + Spatializer
 * - Handles Picture-in-Picture (PiP) and WakeLock/KeepScreenOn
 */
class VedroHardwarePlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.vedro.player/hardware"

        fun register(activity: Activity, messenger: BinaryMessenger) {
            val channel = MethodChannel(messenger, CHANNEL_NAME)
            channel.setMethodCallHandler(VedroHardwarePlugin(activity))
        }
    }

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
            "createVideoSurface" -> result.success(null)
            else -> result.notImplemented()
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
