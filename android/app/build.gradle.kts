import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Membaca kredensial keystore rilis dari android/key.properties (file ini
// TIDAK di-commit ke git, lihat .gitignore). Kalau file belum ada — misalnya
// saat pertama kali clone project di komputer baru — properties akan kosong
// dan build release akan gagal dengan pesan jelas, bukan diam-diam pakai
// kunci debug lagi.
//
// PENTING: Properties()/FileInputStream() di-import eksplisit di baris
// paling atas file ini (bukan ditulis inline sebagai java.util.Properties()/
// java.io.FileInputStream()). Beberapa versi AGP/Gradle terbaru punya
// extension bernama "java" di scope Project yang bentrok dengan reference
// package "java.*" yang ditulis fully-qualified, menyebabkan error
// "Unresolved reference 'util'"/"'io'" walau kodenya sebenarnya valid.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.wtnblasting.app"
    // Dipaksa ke 36 (bukan ikut flutter.compileSdkVersion) karena beberapa
    // plugin (mis. file_picker -> flutter_plugin_android_lifecycle) sudah
    // mensyaratkan compileSdk 36+. Aman dinaikkan; compileSdk cuma menentukan
    // API yang boleh dipakai saat compile, tidak memaksa perangkat pengguna
    // pakai Android versi baru (itu urusan minSdk/targetSdk yang tetap ikut
    // pengaturan Flutter seperti semula).
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wtnblasting.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val storeFilePath: String? = keystoreProperties.getProperty("storeFile")
            storeFile = if (storeFilePath != null) file(storeFilePath) else null
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
