package com.hyperlocal.hyperlocal_shopkeeper_app

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
import kotlinx.coroutines.tasks.await

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.hyperlocal.app/google_auth"
    private lateinit var credentialManager: CredentialManager
    private lateinit var firebaseAuth: FirebaseAuth
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        credentialManager = CredentialManager.create(this)
        firebaseAuth = FirebaseAuth.getInstance()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "signInWithGoogle" -> signInWithGoogle(result)
                "signOut" -> signOut(result)
                "getCurrentUser" -> getCurrentUser(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun signInWithGoogle(result: MethodChannel.Result) {
        pendingResult = result
        CoroutineScope(Dispatchers.Main).launch {
            try {
                // Clear any stale Firebase session + cached Google credential
                // before requesting a fresh one, so an invalid cached token is
                // never replayed to Firebase's SignInWithIdp endpoint.
                try {
                    firebaseAuth.signOut()
                    android.util.Log.d("GoogleAuth", "Cleared previous Firebase session before sign-in")
                } catch (ignored: Exception) {
                    android.util.Log.w("GoogleAuth", "signOut before sign-in failed (continuing anyway): ${ignored.message}")
                }

                // Use explicit web client ID for Credential Manager
                val serverClientId = "356092661742-hcvah5tufmgv5eas4ao4ijqk0vope50o.apps.googleusercontent.com"
                android.util.Log.d("GoogleAuth", "Using serverClientId: $serverClientId")

                val googleIdOption = GetGoogleIdOption.Builder()
                    .setServerClientId(serverClientId)
                    .setFilterByAuthorizedAccounts(false)
                    .setAutoSelectEnabled(false)
                    .build()

                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(googleIdOption)
                    .build()

                android.util.Log.d("GoogleAuth", "Requesting credential from CredentialManager...")
                val credentialResponse = credentialManager.getCredential(
                    request = request,
                    context = this@MainActivity
                )
                android.util.Log.d("GoogleAuth", "Credential received successfully")

                handleCredential(credentialResponse)
            } catch (e: GetCredentialException) {
                android.util.Log.e("GoogleAuth", "GetCredentialException: code=${e.type}, message=${e.message}", e)
                pendingResult?.error("GOOGLE_SIGN_IN_FAILED", "${e.type}: ${e.message}", e.stackTraceToString())
                pendingResult = null
            } catch (e: Exception) {
                android.util.Log.e("GoogleAuth", "Exception: ${e.javaClass.name}, message=${e.message}", e)
                pendingResult?.error("GOOGLE_SIGN_IN_ERROR", "${e.javaClass.name}: ${e.message}", e.stackTraceToString())
                pendingResult = null
            }
        }
    }

    private fun handleCredential(response: GetCredentialResponse) {
        val credential = response.credential
        if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            try {
                val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
                val idToken = googleIdTokenCredential.idToken
                firebaseAuthWithGoogle(idToken)
            } catch (e: Exception) {
                pendingResult?.error("GOOGLE_ID_TOKEN_ERROR", e.message, null)
                pendingResult = null
            }
        } else {
            pendingResult?.error("INVALID_CREDENTIAL", "Not a Google ID token credential", null)
            pendingResult = null
        }
    }

    private fun firebaseAuthWithGoogle(idToken: String) {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val credential = GoogleAuthProvider.getCredential(idToken, null)
                val authResult = firebaseAuth.signInWithCredential(credential).await()
                val user = authResult.user
                if (user != null) {
                    val firebaseIdToken = user.getIdToken(false).await().token
                    val userData = mapOf(
                        "id" to user.uid,
                        "name" to user.displayName,
                        "email" to user.email,
                        "photoUrl" to user.photoUrl?.toString(),
                        "idToken" to firebaseIdToken
                    )
                    pendingResult?.success(userData)
                } else {
                    pendingResult?.error("FIREBASE_USER_NULL", "Firebase user is null", null)
                }
                pendingResult = null
            } catch (e: Exception) {
                pendingResult?.error("FIREBASE_AUTH_ERROR", e.message, null)
                pendingResult = null
            }
        }
    }

    private fun signOut(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                firebaseAuth.signOut()
                result.success(true)
            } catch (e: Exception) {
                result.error("SIGN_OUT_ERROR", e.message, null)
            }
        }
    }

    private fun getCurrentUser(result: MethodChannel.Result) {
        val user = firebaseAuth.currentUser
        if (user != null) {
            CoroutineScope(Dispatchers.Main).launch {
                try {
                    val idToken = user.getIdToken(false).await().token
                    val userData = mapOf(
                        "id" to user.uid,
                        "name" to user.displayName,
                        "email" to user.email,
                        "photoUrl" to user.photoUrl?.toString(),
                        "idToken" to idToken
                    )
                    result.success(userData)
                } catch (e: Exception) {
                    result.error("GET_TOKEN_ERROR", e.message, null)
                }
            }
        } else {
            result.success(null)
        }
    }
}