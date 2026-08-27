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
// Blok ini memaksa SEMUA subproject library Android (termasuk plugin pihak
// ketiga) supaya ikut compile terhadap SDK 36 juga.
// Dipasang lewat plugins.withId (bukan afterEvaluate) supaya jalan tepat
// saat plugin Android-nya di-apply, karena project ini juga memakai
// evaluationDependsOn(":app") yang membuat sebagian subproject sudah
// selesai dievaluasi lebih dulu -> afterEvaluate jadi terlambat & error.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            compileSdk = 36
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
            compileSdk = 36
        }
    }
}

// BUG DIKETAHUI di plugin pihak ketiga "file_picker" (versi 11.0.x, tracked
// di flutter_file_picker#1973): source code Android-nya sudah ditulis dalam
// Kotlin, TAPI build.gradle bawaan paketnya TIDAK menerapkan plugin
// "org.jetbrains.kotlin.android" (kotlin-android) sendiri. Akibatnya file
// .kt milik FilePickerPlugin tidak pernah benar-benar dikompilasi jadi
// .class, dan build gagal di tahap compileDebugJavaWithJavac dengan pesan
// "cannot find symbol ... FilePickerPlugin" — padahal ini murni bug di
// paket file_picker itu sendiri, bukan di kode project ini.
// Blok ini memaksa plugin kotlin-android terpasang untuk subproject
// "file_picker" secara spesifik dari root project, sebagai workaround
// sampai maintainer file_picker merilis versi yang benar-benar
// memperbaikinya. Aman dipasang berdampingan dengan
// android.builtInKotlin=false di gradle.properties (tidak akan bentrok
// dengan Kotlin bawaan AGP 9 karena builtInKotlin sengaja dimatikan).
subprojects {
    if (project.name == "file_picker") {
        plugins.withId("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        // Setelah plugin Kotlin dipasang paksa di atas, compileDebugKotlin
        // ikut default ke versi JDK yang menjalankan Gradle (mis. JDK 25 di
        // komputer developer), sementara compileDebugJavaWithJavac di
        // project ini tetap dipatok ke Java 17 (lihat android/app/build.gradle.kts).
        // Ketidakcocokan ini bikin Gradle menolak build ("Inconsistent JVM
        // Target Compatibility"). Baris ini menyamakan target Kotlin
        // file_picker ke Java 17 juga, supaya konsisten dengan seluruh project.
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
