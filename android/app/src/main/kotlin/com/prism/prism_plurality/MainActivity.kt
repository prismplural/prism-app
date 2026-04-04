package com.prism.prism_plurality

import android.annotation.SuppressLint
import android.app.Activity
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SCREENSHOT_CHANNEL = "com.prism.prism_plurality/screenshot_events"
        private const val SECURE_DISPLAY_CHANNEL = "com.prism.prism_plurality/secure_display"
        private const val FIRST_DEVICE_ADMISSION_CHANNEL =
            "com.prism.prism_plurality/first_device_admission"
        private const val ANDROID_ATTESTATION_CONTEXT = "PRISM_SYNC_ANDROID_ATTEST_V1\u0000"
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
                        if (enabled) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE
                            )
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
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
            if (syncId.isNullOrEmpty() || deviceId.isNullOrEmpty() || nonce.isNullOrEmpty()) {
                result.error("bad_args", "sync_id, device_id, and nonce are required", null)
                return@setMethodCallHandler
            }

            try {
                result.success(collectFirstDeviceAdmissionProof(syncId, deviceId, nonce))
            } catch (t: Throwable) {
                result.error("attestation_failed", t.message, null)
            }
        }
    }

    private fun collectFirstDeviceAdmissionProof(
        syncId: String,
        deviceId: String,
        nonce: String,
    ): Map<String, Any>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return null
        }

        val alias = "prism_sync_attestation_${System.nanoTime()}"
        val challenge = buildAndroidAttestationChallenge(syncId, deviceId, nonce)
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
                null
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
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(ANDROID_ATTESTATION_CONTEXT.toByteArray(Charsets.UTF_8))
        digest.update(syncId.toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
        digest.update(deviceId.toByteArray(Charsets.UTF_8))
        digest.update(byteArrayOf(0))
        digest.update(nonce.toByteArray(Charsets.UTF_8))
        return digest.digest()
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
