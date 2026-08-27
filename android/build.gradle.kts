allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Sebagian plugin (mis. file_picker -> flutter_plugin_android_lifecycle)
// punya build.gradle SENDIRI di dalam paketnya (bukan bagian dari project
// kita) yang tetap ikut compileSdk bawaan Flutter SDK (34), TIDAK ikut
// pengaturan compileSdk=36 yang sudah diset di android/app/build.gradle.kts.
// Blok ini memaksa SEMUA subproject plugin (bukan :app, karena :app sudah
// diatur sendiri di android/app/build.gradle.kts) supaya ikut compile
// terhadap SDK 36. Dipasang via afterEvaluate supaya dijalankan SETELAH
// script asli plugin selesai (kalau dipasang lebih awal, nilainya ketimpa
// lagi oleh baris `compileSdk = flutter.compileSdkVersion` di script asli
// plugin itu sendiri). `:app` dikecualikan supaya tidak bentrok dengan
// `evaluationDependsOn(":app")` di atas (yang bikin :app sudah selesai
// dievaluasi lebih dulu, sehingga afterEvaluate ke :app akan error).
subprojects {
    if (name != "app") {
        afterEvaluate {
            val hasAndroidPlugin = plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")
            if (hasAndroidPlugin) {
                val androidExt = extensions.findByName("android")
                if (androidExt is com.android.build.gradle.BaseExtension) {
                    androidExt.compileSdkVersion(36)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
