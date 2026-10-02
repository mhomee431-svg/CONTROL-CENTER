package com.hyperlocal.app

import android.os.Bundle
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Native Google Sign-In bridge for the Flutter auth layer.
 *
 * Android uses the Credential Manager API (the modern replacement for the
 * deprecated GoogleSignIn client). The resulting Google ID token is exchanged
 * for a Firebase credential, and Firebase's ID token is returned to Dart — the
 * exact same token contract as iOS/web, so the backend verification path
 * (`POST /auth/google-login`) is platform-independent.
 */
class MainActivity : FlutterActivity() {

    private lateinit var credentialManager: CredentialManager
    private lateinit var firebaseAuth: FirebaseAuth

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        credentialManager = CredentialManager.create(this)
        firebaseAuth = FirebaseAuth.getInstance()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "signInWithGoogle" -> signInWithGoogle(result)
                    "signOut" -> signOut(result)
                    "getCurrentUser" -> getCurrentUser(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun signInWithGoogle(result: MethodChannel.Result) {
        // Clear any stale Firebase session before requesting a fresh Google
        // credential, so an invalid cached token is never replayed.
        try {
            firebaseAuth.signOut()
        } catch (_: Exception) {
            // Best-effort — continue with the fresh sign-in request.
        }

        val googleIdOption = GetGoogleIdOption.Builder()
            .setServerClientId(SERVER_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)
            .setAutoSelectEnabled(false)
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()

        // CredentialManager.getCredential() is a *suspend* function as of
        // androidx.credentials 1.3.0 — it returns no Task, so chaining
        // addOnSuccessListener/addOnFailureListener onto it could never compile
        // and the APK never built. Run it on a main-dispatcher coroutine and
        // handle the thrown exceptions, which is exactly how shopkeeper_app's
        // MainActivity drives the same API. kotlinx-coroutines arrives
        // transitively from androidx.credentials.
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val response = credentialManager.getCredential(
                    context = this@MainActivity,
                    request = request,
                )
                handleCredential(response, result)
            } catch (error: GetCredentialException) {
                result.error(mapCredentialErrorCode(error), error.message, null)
            } catch (error: Exception) {
                result.error(mapCredentialErrorCode(error), error.message, null)
            }
        }
    }

    private fun handleCredential(
        response: GetCredentialResponse,
        result: MethodChannel.Result,
    ) {
        val credential = response.credential
        if (credential !is CustomCredential ||
            credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            result.error("INVALID_CREDENTIAL", "Not a Google ID token credential", null)
            return
        }

        val idToken = try {
            GoogleIdTokenCredential.createFrom(credential.data).idToken
        } catch (e: Exception) {
            result.error("GOOGLE_ID_TOKEN_ERROR", e.message, null)
            return
        }

        firebaseAuthWithGoogle(idToken, result)
    }

    private fun firebaseAuthWithGoogle(idToken: String, result: MethodChannel.Result) {
        firebaseAuth
            .signInWithCredential(GoogleAuthProvider.getCredential(idToken, null))
            .addOnSuccessListener { authResult ->
                val user = authResult.user
                if (user == null) {
                    result.error("FIREBASE_USER_NULL", "Firebase user is null", null)
                    return@addOnSuccessListener
                }
                user.getIdToken(false)
                    .addOnSuccessListener { tokenResult ->
                        result.success(
                            mapOf(
                                "id" to user.uid,
                                "name" to user.displayName,
                                "email" to user.email,
                                "photoUrl" to user.photoUrl?.toString(),
                                "idToken" to tokenResult.token,
                            ),
                        )
                    }
                    .addOnFailureListener { error ->
                        result.error("GET_TOKEN_ERROR", error.message, null)
                    }
            }
            .addOnFailureListener { error ->
                result.error("FIREBASE_AUTH_ERROR", error.message, null)
            }
    }

    private fun mapCredentialErrorCode(error: Exception): String {
        val className = error.javaClass.simpleName.lowercase()
        if ("cancel" in className) return "GOOGLE_SIGN_IN_CANCELLED"
        if (error is GetCredentialException &&
            error.type.contains("NO_CREDENTIAL", ignoreCase = true)
        ) {
            return "NO_GOOGLE_ACCOUNTS"
        }
        return "GOOGLE_SIGN_IN_FAILED"
    }

    private fun signOut(result: MethodChannel.Result) {
        try {
            firebaseAuth.signOut()
            result.success(true)
        } catch (e: Exception) {
            result.error("SIGN_OUT_ERROR", e.message, null)
        }
    }

    private fun getCurrentUser(result: MethodChannel.Result) {
        val user = firebaseAuth.currentUser
        if (user == null) {
            result.success(null)
            return
        }
        user.getIdToken(false)
            .addOnSuccessListener { tokenResult ->
                result.success(
                    mapOf(
                        "id" to user.uid,
                        "name" to user.displayName,
                        "email" to user.email,
                        "photoUrl" to user.photoUrl?.toString(),
                        "idToken" to tokenResult.token,
                    ),
                )
            }
            .addOnFailureListener { error ->
                result.error("GET_TOKEN_ERROR", error.message, null)
            }
    }

    companion object {
        private const val CHANNEL = "com.hyperlocal.app/google_auth"

        /**
         * Google **web** OAuth client ID (client_type 3) from
         * `android/app/google-services.json`. Credential Manager requires the
         * server client ID — the Android client ID alone cannot be used here.
         */
        private const val SERVER_CLIENT_ID =
            "356092661742-hcvah5tufmgv5eas4ao4ijqk0vope50o.apps.googleusercontent.com"
    }
}

