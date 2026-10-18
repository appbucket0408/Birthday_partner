import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key lives OUTSIDE the repo; android/key.properties (gitignored)
// only points at it. See android/key.properties.example for the format.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// A release build without the upload key must fail HERE, loudly. Falling back
// to the debug key (the Flutter template's default) produces an artifact Play
// rejects, and a missing signingConfig produces an unsigned one -- both only
// discovered at upload time. Debug and profile builds don't need the key.
val wantsRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (wantsRelease && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "android/key.properties is missing, so this release build cannot be signed. " +
            "Copy android/key.properties.example to android/key.properties and fill it in."
    )
}

android {
    namespace = "com.flutzo.candlewish"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Permanent: Play identifies the app by this forever after the first
        // upload. Firebase is registered against it too (google-services.json).
        applicationId = "com.flutzo.candlewish"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The version flutter_local_notifications 20.x's README specifies.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
