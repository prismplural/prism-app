package com.prism.prism_plurality

import android.annotation.SuppressLint
import android.app.Activity
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SCREENSHOT_CHANNEL = "com.prism.prism_plurality/screenshot_events"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setStreamHandler(ScreenshotStreamHandler())
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
