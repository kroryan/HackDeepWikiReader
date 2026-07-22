import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing has two tiers:
// 1. A real Play Store upload keystore, via android/key.properties
//    (gitignored; see android/.gitignore). CI writes this file from repo
//    secrets when they're configured -- see .github/workflows/release.yml's
//    build-android job and this repo's README for the secret names.
// 2. Falling that, a throwaway, non-secret, INTENTIONALLY COMMITTED
//    "ci-installer-key.jks" (fixed well-known password below) -- so every
//    APK/AAB this repo ever builds (including every CI pre-release, with no
//    setup required) is validly signed, therefore actually installable, and
//    shares one stable signing identity so users can upgrade-install a
//    newer pre-release over an older one instead of needing to uninstall
//    first. This key proves nothing about who built the APK -- it exists
//    purely so "signed" doesn't mean "gatekept behind a secret nobody set
//    up yet".
val ciInstallerKeystore = file("ci-installer-key.jks")
val ciInstallerPassword = "hackdeepwikireader-ci-installer"

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kroryan.hackdeepwikireader"
    compileSdk = flutter.compileSdkVersion
    // Pinned above flutter.ndkVersion: file_picker/path_provider_android/
    // url_launcher_android/flutter_plugin_android_lifecycle all require
    // 27.0.12077973, and NDK versions are backward compatible.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kroryan.hackdeepwikireader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
        create("ciInstaller") {
            keyAlias = "ci"
            keyPassword = ciInstallerPassword
            storeFile = ciInstallerKeystore
            storePassword = ciInstallerPassword
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("ciInstaller")
        }
    }
}

flutter {
    source = "../.."
}
