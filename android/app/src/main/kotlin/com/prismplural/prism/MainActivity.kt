package com.prismplural.prism

import android.annotation.SuppressLint
import android.app.Activity
import android.app.KeyguardManager
import android.content.ClipDescription
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import android.provider.MediaStore
import android.security.keystore.KeyInfo
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import android.util.Log
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.KeyStoreException
import java.security.MessageDigest
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import java.security.InvalidAlgorithmParameterException
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import javax.crypto.AEADBadTagException
import javax.crypto.BadPaddingException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "PrismMainActivity"
        private const val SCREENSHOT_CHANNEL = "com.prism.prism_plurality/screenshot_events"
        private const val SECURE_DISPLAY_CHANNEL = "com.prism.prism_plurality/secure_display"
        private const val FIRST_DEVICE_ADMISSION_CHANNEL =
            "com.prism.prism_plurality/first_device_admission"
        private const val RUNTIME_DEK_WRAP_CHANNEL =
            "com.prism.prism_plurality/runtime_dek_wrap"
        private const val APP_CLIPBOARD_CHANNEL =
            "com.prism.prism_plurality/app_clipboard"
        private const val ANDROID_ATTESTATION_CONTEXT = "PRISM_SYNC_ANDROID_ATTEST_V2\u0000"
        private const val RUNTIME_DEK_KEY_ALIAS = "prism_runtime_dek_wrap_v1"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setStreamHandler(ScreenshotStreamHandler())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_DISPLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureDisplay" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        // setFlags mutates window attributes and won't
                        // throw on a stale/destroyed Activity, so an
                        // early lifecycle guard is the only way to keep
                        // Dart from caching _platformStateOn = true while
                        // the visible window has no FLAG_SECURE. On
                        // failure, propagate as PlatformException so
                        // ScreenSecurityService retries on the next
                        // reconcile.
                        if (isFinishing || isDestroyed) {
                            Log.w(
                                TAG,
                                "setSecureDisplay($enabled) skipped — Activity finishing/destroyed"
                            )
                            result.error(
                                "SECURE_DISPLAY_FAILED",
                                "Activity is finishing or destroyed",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            if (enabled) {
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                    WindowManager.LayoutParams.FLAG_SECURE
                                )
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            // Narrower than Throwable on purpose: don't
                            // swallow OutOfMemoryError / LinkageError /
                            // other JVM Errors that should crash loud.
                            Log.w(TAG, "setSecureDisplay($enabled) failed", e)
                            result.error(
                                "SECURE_DISPLAY_FAILED",
                                "Could not apply secure display change: ${e.message}",
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FIRST_DEVICE_ADMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "collectFirstDeviceAdmissionProof") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val syncId = call.argument<String>("sync_id")
            val deviceId = call.argument<String>("device_id")
            val nonce = call.argument<String>("nonce")
            val registrationKeyBundleHash = call.argument<String>("registration_key_bundle_hash")
            if (
                syncId.isNullOrEmpty() ||
                deviceId.isNullOrEmpty() ||
                nonce.isNullOrEmpty() ||
                registrationKeyBundleHash.isNullOrEmpty()
            ) {
                result.error(
                    "permanent_failure",
                    "sync_id, device_id, nonce, and registration_key_bundle_hash are required",
                    null,
                )
                return@setMethodCallHandler
            }

            try {
                result.success(
                    collectFirstDeviceAdmissionProof(
                        syncId,
                        deviceId,
                        nonce,
                        registrationKeyBundleHash,
                    ),
                )
            } catch (e: PlatformAttestationException) {
                result.error(e.code, e.message, null)
            } catch (e: IllegalArgumentException) {
                result.error("permanent_failure", e.message, null)
            } catch (t: Throwable) {
                result.error("transient_failure", t.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RUNTIME_DEK_WRAP_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "wrapRuntimeDek" -> {
                        val dek = call.argument<ByteArray>("dek")
                        val aad = call.argument<String>("aad")
                        if (dek == null || dek.isEmpty()) {
                            result.error("bad_args", "dek is required", null)
                            return@setMethodCallHandler
                        }
                        if (aad.isNullOrEmpty()) {
                            result.error("bad_args", "aad is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(wrapRuntimeDek(dek, aad))
                    }
                    "unwrapRuntimeDek" -> result.success(unwrapRuntimeDek(call.arguments))
                    "deleteRuntimeDekWrappingKey" -> {
                        deleteRuntimeDekWrappingKey()
                        result.success(null)
                    }
                    "getRuntimeDekDiagnostics" ->
                        result.success(collectRuntimeDekDiagnostics())
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                // Classify only on the unwrap path. The Dart-side cache logic
                // uses the code to decide whether the wrapped runtime DEK
                // blob should be discarded (terminal: blob/key gone for good)
                // or preserved for a retry next launch (transient: device-
                // lock state, StrongBox flake, etc.). Wrap and delete failures
                // don't drive cache eviction, so they keep the legacy code.
                val code = if (call.method == "unwrapRuntimeDek") {
                    classifyRuntimeDekUnwrapFailure(t)
                } else {
                    "runtime_dek_wrap_failed"
                }
                result.error(code, t.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_CLIPBOARD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readImage" -> {
                        val pasteboard = call.argument<String>("pasteboard") ?: "clipboard"
                        result.success(
                            if (pasteboard == "clipboard") readClipboardImageBytes() else null
                        )
                    }
                    "readImageUri" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrEmpty()) {
                            result.success(null)
                        } else {
                            result.success(readImageUriBytes(Uri.parse(uri)))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Unable to read clipboard image", t)
                result.success(null)
            }
        }
    }

    private fun readClipboardImageBytes(): ByteArray? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            ?: return null
        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null

        val description = clip.description
        for (index in 0 until clip.itemCount) {
            val item = clip.getItemAt(index)
            val uri = item.uri ?: item.intent?.data ?: continue
            val mimeType = contentResolver.getType(uri)
            val looksLikeImage =
                mimeType?.startsWith("image/") == true ||
                    (mimeType == null && clip.itemCount == 1 && hasImageMimeType(description))
            if (looksLikeImage) {
                return readImageUriBytes(uri)
            }
        }

        return null
    }

    private fun readImageUriBytes(uri: Uri): ByteArray? {
        return contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }

    private fun hasImageMimeType(description: ClipDescription?): Boolean {
        if (description == null) return false
        for (index in 0 until description.mimeTypeCount) {
            if (description.getMimeType(index).startsWith("image/")) {
                return true
            }
        }
        return false
    }

    private fun wrapRuntimeDek(dek: ByteArray, aad: String): Map<String, Any> {
        val wrappingKey = getOrCreateRuntimeDekWrappingKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        val ciphertext = cipher.doFinal(dek)
        return mapOf(
            "version" to 1,
            "platform" to "android_keystore_aes_gcm",
            "iv" to Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            "ciphertext" to Base64.encodeToString(ciphertext, Base64.NO_WRAP),
            "key_security" to runtimeDekKeySecurity(wrappingKey),
        )
    }

    private fun unwrapRuntimeDek(arguments: Any?): ByteArray {
        val args = arguments as? Map<*, *>
            ?: throw IllegalArgumentException("wrapped runtime DEK blob is required")
        val aad = args["aad"] as? String
            ?: throw IllegalArgumentException("aad is required")
        val iv = Base64.decode(args["iv"] as? String ?: "", Base64.NO_WRAP)
        val ciphertext = Base64.decode(args["ciphertext"] as? String ?: "", Base64.NO_WRAP)

        // Use the existing-only path: never auto-generate during unwrap.
        // A transient lookup failure on the existing alias must surface as
        // a TRANSIENT classification (so the cache survives), not as an
        // accidental key replacement that would orphan the wrapped blob.
        val key = getExistingRuntimeDekWrappingKey()

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(ciphertext)
    }

    /**
     * Loads the existing runtime DEK wrapping key without ever generating
     * one. Distinguishes "alias genuinely missing" (terminal — the cached
     * blob can never be unwrapped, throw [UnrecoverableKeyException]) from
     * "alias present but getKey returned null" (transient — fall back via
     * [KeyStoreException] which the classifier maps to retry).
     *
     * Splitting this from [getOrCreateRuntimeDekWrappingKey] is load-bearing:
     * the previous implementation called the or-create path during unwrap,
     * so a transient `getKey` failure would silently generate a new key,
     * permanently orphaning the existing wrapped blob.
     */
    private fun getExistingRuntimeDekWrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!keyStore.containsAlias(RUNTIME_DEK_KEY_ALIAS)) {
            throw UnrecoverableKeyException(
                "Runtime DEK wrapping key alias '$RUNTIME_DEK_KEY_ALIAS' " +
                    "not present in AndroidKeyStore"
            )
        }
        val key = keyStore.getKey(RUNTIME_DEK_KEY_ALIAS, null) as? SecretKey
            ?: throw KeyStoreException(
                "Runtime DEK wrapping key alias '$RUNTIME_DEK_KEY_ALIAS' " +
                    "present but getKey() returned null (transient)"
            )
        return key
    }

    private fun getOrCreateRuntimeDekWrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(RUNTIME_DEK_KEY_ALIAS, null) as? SecretKey)?.let { return it }

        if (shouldTryStrongBox()) {
            try {
                val strongBoxKey = generateRuntimeDekWrappingKey(strongBoxBacked = true)
                Log.i(TAG, "Generated runtime DEK wrapping key with StrongBox requested")
                return strongBoxKey
            } catch (e: StrongBoxUnavailableException) {
                Log.i(TAG, "StrongBox unavailable for runtime DEK wrapping key; falling back", e)
            } catch (e: InvalidAlgorithmParameterException) {
                Log.i(TAG, "StrongBox rejected runtime DEK wrapping key parameters; falling back", e)
            } catch (e: ProviderException) {
                Log.i(TAG, "StrongBox provider failed for runtime DEK wrapping key; falling back", e)
            }
        } else {
            Log.i(TAG, "StrongBox not reported for this device; generating runtime DEK key normally")
        }

        return generateRuntimeDekWrappingKey(strongBoxBacked = false)
    }

    private fun generateRuntimeDekWrappingKey(strongBoxBacked: Boolean): SecretKey {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(runtimeDekKeySpec(strongBoxBacked))
        return generator.generateKey()
    }

    private fun runtimeDekKeySpec(strongBoxBacked: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            RUNTIME_DEK_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)

        if (strongBoxBacked && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            // Android documents Android 12-14 bugs for unlocked-device-required
            // keys: generation/use failures without secure lock screen,
            // deletion after lock-screen removal, and biometric reauthorization
            // gaps. Android 15 fixes those issues, so keep the initial gate at
            // API 35+ rather than applying this to Android 12-14 devices.
            builder.setUnlockedDeviceRequired(true)
        }

        return builder.build()
    }

    private fun shouldTryStrongBox(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)

    @SuppressLint("NewApi")
    private fun runtimeDekKeySecurity(key: SecretKey): Map<String, Any> {
        val metadata = mutableMapOf<String, Any>()
        val keyInfo = runCatching {
            SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
                .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        }.getOrNull()

        @Suppress("DEPRECATION")
        metadata["inside_secure_hardware"] = keyInfo?.isInsideSecureHardware == true
        if (keyInfo != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            metadata["security_level"] = when (keyInfo.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "trusted_environment"
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
                KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> "unknown_secure"
                else -> "unknown"
            }
            metadata["strongbox_backed"] =
                keyInfo.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        }
        metadata["unlocked_device_required_policy"] =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                "enabled_api_35_plus"
            } else {
                "not_enabled_android_12_14_caveat"
            }
        return metadata
    }

    /**
     * Maps a Throwable from `unwrapRuntimeDek` into one of three Dart-facing
     * codes so the Dart cache logic can react appropriately:
     *   - `runtime_dek_wrap_terminal`: blob is unrecoverable; cache should
     *     be discarded.
     *   - `runtime_dek_wrap_transient`: temporary failure (device locked at
     *     evaluation time, StrongBox briefly unavailable); a retry next
     *     launch is expected to succeed. Cache must be preserved.
     *   - `runtime_dek_wrap_failed`: legacy/unknown — Dart treats as
     *     "preserve cache" by default to avoid spuriously invalidating a
     *     viable blob on a failure mode we haven't classified yet.
     *
     * Walks the cause chain because Cipher operations wrap Keystore errors
     * inside generic exceptions on some OEM devices.
     */
    private fun classifyRuntimeDekUnwrapFailure(throwable: Throwable): String {
        var current: Throwable? = throwable
        val seen = HashSet<Throwable>()
        while (current != null && seen.add(current)) {
            // android.security.KeyStoreException (API 30+) is a SEPARATE
            // type from java.security.KeyStoreException — different
            // package, different inheritance tree. The diagnostic methods
            // (isTransientFailure, requiresUserAuthentication,
            // getNumericErrorCode) are API 33+. Detect by name to avoid
            // a hard runtime dependency on minSdk 30+.
            if (current::class.java.name == "android.security.KeyStoreException") {
                return classifyAndroidKeyStoreException(current)
            }
            when (current) {
                // Hard terminal: the wrapping key is gone or the blob
                // can't be authenticated against any key we hold.
                is KeyPermanentlyInvalidatedException,
                is UnrecoverableKeyException,
                is AEADBadTagException,
                is BadPaddingException,
                is IllegalArgumentException ->
                    return "runtime_dek_wrap_terminal"

                // Transient: device-lock state at eval time, secure
                // element flake, key-validity-window race. Retrying on a
                // future launch is expected to succeed.
                is UserNotAuthenticatedException,
                is StrongBoxUnavailableException,
                is KeyStoreException ->
                    return "runtime_dek_wrap_transient"
            }
            current = current.cause
        }
        return "runtime_dek_wrap_failed"
    }

    /**
     * Classifies an android.security.KeyStoreException via reflection
     * (the class is API 30+; diagnostic methods are API 33+). Treats
     * isTransientFailure() / requiresUserAuthentication() as transient.
     * Other API-33+ verdicts default to terminal (the keystore says this
     * is the permanent answer). On API 30-32 the diagnostic methods are
     * absent, default to transient — these are most commonly thrown for
     * retryable device-state issues.
     */
    private fun classifyAndroidKeyStoreException(e: Throwable): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val cls = e::class.java
                val isTransient = cls.getMethod("isTransientFailure")
                    .invoke(e) as? Boolean ?: false
                if (isTransient) return "runtime_dek_wrap_transient"
                val requiresAuth = cls.getMethod("requiresUserAuthentication")
                    .invoke(e) as? Boolean ?: false
                if (requiresAuth) return "runtime_dek_wrap_transient"
                return "runtime_dek_wrap_terminal"
            } catch (_: Throwable) {
                // Fall through to default below.
            }
        }
        return "runtime_dek_wrap_transient"
    }

    private fun deleteRuntimeDekWrappingKey() {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(RUNTIME_DEK_KEY_ALIAS)) {
            keyStore.deleteEntry(RUNTIME_DEK_KEY_ALIAS)
        }
    }

    /**
     * Returns a snapshot of runtime-DEK-relevant Keystore + device state
     * for diagnostic surfacing in the Crypto storage debug screen. All
     * fields are read-only — this MUST NOT mutate the keystore (no
     * generate-on-miss, no test-unwrap).
     *
     * Output map shape:
     *   - alias_present: Boolean — keystore.containsAlias check.
     *   - get_key_succeeded: Boolean? — null if alias missing; otherwise
     *     true/false based on whether SecretKey load returned non-null.
     *   - key_security: Map<String, Any>? — security level + StrongBox +
     *     unlocked-device-required policy, if alias resolves.
     *   - device_state: Map<String, Any> — KeyguardManager + UserManager
     *     state (locked, user unlocked) at the moment of capture.
     *   - build: Map<String, String> — manufacturer / model / sdk_int /
     *     security_patch for OEM diagnosis.
     */
    private fun collectRuntimeDekDiagnostics(): Map<String, Any?> {
        val out = HashMap<String, Any?>()

        var aliasPresent = false
        var getKeySucceeded: Boolean? = null
        var keySecurity: Map<String, Any>? = null
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            aliasPresent = keyStore.containsAlias(RUNTIME_DEK_KEY_ALIAS)
            if (aliasPresent) {
                val key = keyStore.getKey(RUNTIME_DEK_KEY_ALIAS, null) as? SecretKey
                getKeySucceeded = key != null
                if (key != null) {
                    keySecurity = runtimeDekKeySecurity(key)
                }
            }
        } catch (t: Throwable) {
            out["keystore_introspection_error"] =
                "${t::class.java.simpleName}: ${t.message ?: ""}"
        }
        out["alias_present"] = aliasPresent
        out["get_key_succeeded"] = getKeySucceeded
        out["key_security"] = keySecurity

        val deviceState = HashMap<String, Any?>()
        try {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (km != null) {
                deviceState["is_keyguard_locked"] = km.isKeyguardLocked
                deviceState["is_keyguard_secure"] = km.isKeyguardSecure
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    deviceState["is_device_locked"] = km.isDeviceLocked
                    deviceState["is_device_secure"] = km.isDeviceSecure
                }
            }
            val um = getSystemService(Context.USER_SERVICE) as? UserManager
            if (um != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                deviceState["is_user_unlocked"] = um.isUserUnlocked
            }
        } catch (t: Throwable) {
            deviceState["device_state_error"] =
                "${t::class.java.simpleName}: ${t.message ?: ""}"
        }
        out["device_state"] = deviceState

        out["build"] = mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: "unknown"),
            "model" to (Build.MODEL ?: "unknown"),
            "device" to (Build.DEVICE ?: "unknown"),
            "sdk_int" to Build.VERSION.SDK_INT,
            "security_patch" to (Build.VERSION.SECURITY_PATCH ?: "unknown"),
        )

        return out
    }

    private fun collectFirstDeviceAdmissionProof(
        syncId: String,
        deviceId: String,
        nonce: String,
        registrationKeyBundleHash: String,
    ): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            throw PlatformAttestationException(
                "missing_api",
                "Android Key Attestation requires Android 7.0 or newer",
            )
        }

        val alias = "prism_sync_attestation_${System.nanoTime()}"
        val challenge = buildAndroidAttestationChallenge(
            syncId,
            deviceId,
            nonce,
            registrationKeyBundleHash,
        )
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

        return try {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore",
            )
            val spec = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setAttestationChallenge(challenge)
                .setUserAuthenticationRequired(false)
                .build()
            generator.initialize(spec)
            generator.generateKeyPair()

            val certificates = keyStore.getCertificateChain(alias)
                ?.mapNotNull { cert -> (cert as? X509Certificate)?.encoded }
                ?.map { der -> Base64.encodeToString(der, Base64.NO_WRAP) }
                .orEmpty()
            if (certificates.isEmpty()) {
                throw PlatformAttestationException(
                    "transient_failure",
                    "Android Keystore returned no attestation certificate chain",
                )
            } else {
                mapOf(
                    "kind" to "android_key_attestation",
                    "certificate_chain" to certificates,
                )
            }
        } finally {
            runCatching { keyStore.deleteEntry(alias) }
        }
    }

    private fun buildAndroidAttestationChallenge(
        syncId: String,
        deviceId: String,
        nonce: String,
        registrationKeyBundleHash: String,
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(ANDROID_ATTESTATION_CONTEXT.toByteArray(Charsets.UTF_8))
        digest.update(syncId.toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
        digest.update(deviceId.toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
        digest.update(nonce.toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
        digest.update(hexToBytes(registrationKeyBundleHash))
        return digest.digest()
    }

    private class PlatformAttestationException(
        val code: String,
        message: String,
    ) : Exception(message)

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "hex value must have even length" }
        return ByteArray(hex.length / 2) { index ->
            val offset = index * 2
            hex.substring(offset, offset + 2).toInt(16).toByte()
        }
    }

    inner class ScreenshotStreamHandler : EventChannel.StreamHandler {
        private var contentObserver: ContentObserver? = null

        // Stored reference so we can unregister the API 34+ callback in onCancel.
        @SuppressLint("NewApi")
        private var screenCaptureCallback: Activity.ScreenCaptureCallback? = null

        @SuppressLint("NewApi")
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // API 34+ (Android 14+): official screen capture callback.
                // Use mainExecutor (avoids creating a disposable thread pool).
                val callback = Activity.ScreenCaptureCallback {
                    events.success(null)
                }
                registerScreenCaptureCallback(mainExecutor, callback)
                screenCaptureCallback = callback
            } else {
                // API < 34: observe MediaStore for new images in Screenshot folders.
                // We must query file metadata — the content:// URI itself never
                // contains the word "screenshot".
                val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean, uri: Uri?) {
                        if (uri == null) return
                        val isScreenshot = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            // API 29+: use RELATIVE_PATH (e.g. "Pictures/Screenshots/")
                            val projection = arrayOf(MediaStore.Images.Media.RELATIVE_PATH)
                            contentResolver.query(uri, projection, null, null, null)
                                ?.use { cursor ->
                                    if (!cursor.moveToFirst()) return@use false
                                    val idx = cursor.getColumnIndex(
                                        MediaStore.Images.Media.RELATIVE_PATH
                                    )
                                    if (idx < 0) return@use false
                                    cursor.getString(idx)
                                        ?.contains("screenshot", ignoreCase = true) == true
                                } == true
                        } else {
                            // API < 29: use absolute DATA path
                            @Suppress("DEPRECATION")
                            val projection = arrayOf(MediaStore.Images.Media.DATA)
                            contentResolver.query(uri, projection, null, null, null)
                                ?.use { cursor ->
                                    if (!cursor.moveToFirst()) return@use false
                                    @Suppress("DEPRECATION")
                                    val idx = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                                    if (idx < 0) return@use false
                                    cursor.getString(idx)
                                        ?.contains("screenshot", ignoreCase = true) == true
                                } == true
                        }
                        if (isScreenshot) events.success(null)
                    }
                }
                contentResolver.registerContentObserver(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    true,
                    observer,
                )
                contentObserver = observer
            }
        }

        @SuppressLint("NewApi")
        override fun onCancel(arguments: Any?) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                screenCaptureCallback?.let { unregisterScreenCaptureCallback(it) }
                screenCaptureCallback = null
            } else {
                contentObserver?.let { contentResolver.unregisterContentObserver(it) }
                contentObserver = null
            }
        }
    }
}
