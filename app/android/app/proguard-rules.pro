# Keep Vedro native hardware bridge & JNI / FFI classes intact under R8 shrinking
-keep class com.vedro.player.** { *; }
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keep class com.alexmercerind.media_kit** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
