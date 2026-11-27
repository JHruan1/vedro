import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val releaseStoreFilePath = keystoreProperties.getProperty("storeFile")
    ?: System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = keystoreProperties.getProperty("storePassword")
    ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")
    ?: System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")
    ?: System.getenv("ANDROID_KEY_PASSWORD")

val releaseStoreFile = releaseStoreFilePath?.let { path ->
    val direct = file(path)
    if (direct.exists()) direct else rootProject.file(path)
}

val hasReleaseSigning = !releaseStoreFilePath.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank() &&
    (releaseStoreFile?.exists() == true)

if (System.getenv("REQUIRE_RELEASE_SIGNING") == "true" && !hasReleaseSigning) {
    throw GradleException(
        "REQUIRE_RELEASE_SIGNING=true but Android release keystore is not configured. " +
            "Provide app/android/key.properties or ANDROID_KEYSTORE_* environment variables."
    )
}

android {
    namespace = "com.vedro.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vedro.player"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Restrict packaged ABIs to match compiled Rust `libvedro_ffi.so` (excludes sherpa-onnx x86)
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile!!
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
