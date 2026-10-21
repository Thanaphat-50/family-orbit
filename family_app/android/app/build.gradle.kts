import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Firebase (ต้องมี android/app/google-services.json — ไฟล์นี้ไม่ขึ้น Git)
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// =====================================================
// Release Signing (กุญแจอัปโหลดสำหรับ Play Store)
//
// อ่านจาก android/key.properties (ไฟล์นี้ไม่ขึ้น Git)
// ถ้ายังไม่มีไฟล์ หรือกรอกไม่ครบ → เซ็นด้วย debug key ชั่วคราว
// (Play Store ไม่รับไฟล์ที่เซ็นด้วย debug key)
// =====================================================

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun keystoreValue(name: String): String? =
    keystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

val releaseStoreFile = keystoreValue("storeFile")?.let { file(it) }

val hasReleaseKey =
    releaseStoreFile?.exists() == true &&
        listOf("storePassword", "keyAlias", "keyPassword").all { keystoreValue(it) != null }

if (!hasReleaseKey) {
    logger.warn(
        "Release signing key is not configured (android/key.properties). " +
            "Release builds will use the debug key and cannot be uploaded to Google Play.",
    )
}

android {
    namespace = "com.familyorbit.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // ชื่อแอปบน Play Store — เปลี่ยนไม่ได้หลังอัปโหลดครั้งแรก
        applicationId = "com.familyorbit.app"
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
        if (hasReleaseKey) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreValue("storePassword")
                keyAlias = keystoreValue("keyAlias")
                keyPassword = keystoreValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) {
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
