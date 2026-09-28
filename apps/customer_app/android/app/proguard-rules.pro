# ProGuard / R8 rules for the Hyperlocal Customer App
# Dart code is AOT-compiled and is NOT affected by these rules.
# These rules cover the Android (Java/Kotlin) platform layer and any
# third-party AARs pulled in by Flutter plugins.

# --- Flutter engine ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.FlutterApplication { *; }
-keep class io.flutter.plugin.platform.** { *; }
-dontwarn io.flutter.**

# --- Flutter plugins: generated plugin registrant ---
-keep class io.flutter.generated.** { *; }
-keep class io.flutter.embedding.** { *; }

# --- google_maps_flutter ---
-keep class io.flutter.plugins.googlemaps.** { *; }
-keep class com.google.android.libraries.maps.** { *; }
-keep class com.google.android.m4b.maps.** { *; }
-dontwarn com.google.android.libraries.maps.**
-dontwarn com.google.android.m4b.maps.**
-dontwarn okhttp3.**
-dontwarn okio.**

# --- geolocator ---
-keep class io.flutter.plugins.geolocator.** { *; }
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.gms.**

# --- flutter_secure_storage ---
-keep class io.flutter.plugins.fluttersecurestorage.** { *; }

# --- shared_preferences ---
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# --- connectivity_plus ---
-keep class io.flutter.plugins.connectivity.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# --- firebase_auth + Google Credential Manager (native Google Sign-In) ---
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
-keep class androidx.credentials.** { *; }
-dontwarn androidx.credentials.**
-dontwarn com.google.android.libraries.identity.googleid.**

# --- General: keep native methods ---
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Suppress warnings from support libraries ---
-dontwarn androidx.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.**
-dontwarn com.google.errorcorrect.**

# --- Keep generic type signatures for serialization ---
-keepattributes Signature, InnerClasses, EnclosingMethod, EnclosingClass, MemberClasses, Exceptions, *Annotation*
