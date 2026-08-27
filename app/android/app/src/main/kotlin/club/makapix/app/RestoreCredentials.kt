package club.makapix.app

import android.app.Activity
import android.os.Handler
import android.os.Looper
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CreateRestoreCredentialRequest
import androidx.credentials.CreateRestoreCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetRestoreCredentialOption
import androidx.credentials.RestoreCredential
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Zero-Tap Sign-In bridge: Android Restore Credentials over Credential Manager.
 *
 * Google Play requires this from April 2027 for any app with sign-in — a user who migrates to a
 * new device must be signed back in silently on first launch. The credential is passkey-shaped
 * (ordinary WebAuthn on the server); this class only shuttles opaque JSON between Dart and
 * Credential Manager and never inspects or constructs it. See docs/zero-tap-signin/DESIGN.md.
 *
 * Deliberately the **callback** API (`*Async`) rather than the suspend one, so no coroutines
 * dependency is needed for three calls. Callbacks arrive on a background executor, so every
 * `MethodChannel.Result` is posted back to the main looper — Flutter requires that.
 *
 * Every failure is reported to Dart as a plain result, never as a crash: Zero-Tap is an
 * enhancement, and the app must always fall through to the normal signed-out start.
 */
class RestoreCredentials(private val activity: Activity) {

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val manager by lazy { CredentialManager.create(activity) }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(call, result)
            "get" -> get(call, result)
            "clear" -> clear(result)
            else -> result.notImplemented()
        }
    }

    // Reply on the main thread, exactly once. Both return Unit deliberately (not Handler.post's
    // Boolean) so callback overrides can use expression bodies.
    private fun ok(result: MethodChannel.Result, value: Any?) {
        main.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, e: Throwable?) {
        main.post { result.error(code, e?.message ?: code, e?.javaClass?.simpleName) }
    }

    /**
     * Register a restore credential for the signed-in account.
     *
     * [requestJson] is the server's WebAuthn `PublicKeyCredentialCreationOptionsJSON`, passed
     * through verbatim — the RP ID inside it is chosen by the server, which is what lets dev and
     * prod differ without any branching on this side.
     *
     * `isCloudBackupEnabled=false` is the documented fallback when the device has no screen lock
     * or backup is off; Dart drives that retry so the policy stays in one place.
     */
    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val requestJson = call.argument<String>("requestJson")
        if (requestJson.isNullOrEmpty()) {
            fail(result, "bad_args", IllegalArgumentException("requestJson is required"))
            return
        }
        val allowCloud = call.argument<Boolean>("allowCloud") ?: true
        val request = CreateRestoreCredentialRequest(requestJson, allowCloud)

        manager.createCredentialAsync(
            activity,
            request,
            null,
            io,
            object : CredentialManagerCallback<androidx.credentials.CreateCredentialResponse, CreateCredentialException> {
                override fun onResult(response: androidx.credentials.CreateCredentialResponse) {
                    val json = (response as? CreateRestoreCredentialResponse)?.responseJson
                    if (json == null) {
                        fail(result, "create_failed", IllegalStateException("unexpected response type"))
                    } else {
                        ok(result, json)
                    }
                }

                override fun onError(e: CreateCredentialException) {
                    // Matched by simple name rather than importing the concrete class: the
                    // restore-specific exception has moved package between library versions, and a
                    // wrong import is a compile error for what is only a branch hint. Dart decides
                    // what to do with the code.
                    val code = if (e.javaClass.simpleName == "E2eeUnavailableException") {
                        "e2ee_unavailable"
                    } else {
                        "create_failed"
                    }
                    fail(result, code, e)
                }
            },
        )
    }

    /**
     * Attempt a silent assertion on a freshly migrated device.
     *
     * Returns the authentication response JSON, or **null** when there is simply no credential to
     * restore — the overwhelmingly common case (a normal first install). That is not an error and
     * must not be logged as one.
     */
    private fun get(call: MethodCall, result: MethodChannel.Result) {
        val requestJson = call.argument<String>("requestJson")
        if (requestJson.isNullOrEmpty()) {
            fail(result, "bad_args", IllegalArgumentException("requestJson is required"))
            return
        }
        val request = GetCredentialRequest(listOf(GetRestoreCredentialOption(requestJson)))

        manager.getCredentialAsync(
            activity,
            request,
            null,
            io,
            object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                override fun onResult(response: GetCredentialResponse) {
                    ok(result, (response.credential as? RestoreCredential)?.authenticationResponseJson)
                }

                override fun onError(e: GetCredentialException) {
                    // "No credential" is the normal path on a clean install, not a failure.
                    if (e.javaClass.simpleName == "NoCredentialException") ok(result, null)
                    else fail(result, "get_failed", e)
                }
            },
        )
    }

    /** Drop the local restore credential. Called on explicit sign-out only. */
    private fun clear(result: MethodChannel.Result) {
        manager.clearCredentialStateAsync(
            ClearCredentialStateRequest(ClearCredentialStateRequest.TYPE_CLEAR_RESTORE_CREDENTIAL),
            null,
            io,
            object : CredentialManagerCallback<Void?, ClearCredentialException> {
                override fun onResult(response: Void?) = ok(result, null)
                override fun onError(e: ClearCredentialException) = fail(result, "clear_failed", e)
            },
        )
    }
}
