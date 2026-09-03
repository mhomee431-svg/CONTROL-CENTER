import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -- Google Maps API key (Phase 15) -----------------------------------------
// The key is injected at build time - never committed. Resolution order:
//   1. MAPS_API_KEY environment variable   (CI / flutter build --dart-define passthrough)
//   2. MAPS_API_KEY in android/local.properties  (local dev; file is gitignored)
//   3. empty -> the app falls back to the stub map provider
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}
val mapsApiKey: String =
    System.getenv("MAPS_API_KEY")
        ?: localProperties.getProperty("MAPS_API_KEY")
        ?: (project.findProperty("MAPS_API_KEY") as String?)
        ?: ""

// -- Release signing (Phase 27) -------------------------------------------
// Reads key.properties (gitignored). Falls back to environment variables
// for CI injection so passwords are never committed to the repository.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("app/key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val releaseStorePassword: String =
    System.getenv("KEYSTORE_PASSWORD")
        ?: keyProperties.getProperty("storePassword")
        ?: ""
val releaseKeyPassword: String =
    System.getenv("KEY_PASSWORD")
        ?: keyProperties.getProperty("keyPassword")
        ?: ""
val releaseKeyAlias: String =
    keyProperties.getProperty("keyAlias") ?: "hyperlocal_release"
val releaseStoreFile: String =
    keyProperties.getProperty("storeFile") ?: "release.keystore"

android {
    namespace = "com.hyperlocal.hyperlocal_customer_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hyperlocal.hyperlocal_customer_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // google_maps_flutter_android requires an Android SDK level of at least 24.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Manifest placeholder resolved in AndroidManifest.xml as ${MAPS_API_KEY}.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            storeFile = file(releaseStoreFile)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            // Signed with the production keystore (see key.properties, gitignored).
            signingConfig = signingConfigs.getByName("release")
            // R8 code shrinking + resource shrinking for a smaller, hardened APK.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
