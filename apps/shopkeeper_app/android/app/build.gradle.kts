import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services plugin for Firebase
    id("com.google.gms.google-services")
}

// -- Google Maps API key (Phase 15) -----------------------------------------
// The key is injected at build time - never committed. Resolution order:
//   1. MAPS_API_KEY environment variable   (CI / flutter build --dart-define passthrough)
//   2. MAPS_API_KEY in android/local.properties  (local dev; file is gitignored)
//   3. empty -> the map surface renders blank; GPS capture still works
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

android {
    namespace = "com.hyperlocal.hyperlocal_shopkeeper_app"
    // 37 required by permission_handler_android 14.x (was 36 for
    // flutter_plugin_android_lifecycle / flutter_secure_storage deps)
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Application ID must match the package name registered in Firebase Console
        // (case-sensitive: google-services.json declares "com.hyperlocal.app").
        //
        // KNOWN ISSUE — duplicate applicationId: apps/customer_app ships the SAME
        // "com.hyperlocal.app" id, and both apps share one Firebase Android app
        // registration (project local-pier-506805-g5). Two apps cannot be published
        // to the Play Store under one id. Fix order matters:
        //   1. Firebase Console -> add a NEW Android app for the shopkeeper
        //      (e.g. com.hyperlocal.shopkeeper) inside the same project.
        //   2. Replace apps/shopkeeper_app/android/app/google-services.json with the
        //      file downloaded for that new app.
        //   3. ONLY THEN change applicationId below to the new id.
        // Doing 3 before 1-2 fails the build ("No matching client found for package
        // name") and breaks Google Sign-In.
        applicationId = "com.hyperlocal.app"
        // 23 required by google_maps_flutter / androidx.window deps
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Manifest placeholder resolved in AndroidManifest.xml as ${MAPS_API_KEY}.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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

// Firebase + Credential Manager dependencies
dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.18.0"))
    implementation("com.google.firebase:firebase-auth")

    // Credential Manager & Google ID libraries (modern Google Sign-In)
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
}
