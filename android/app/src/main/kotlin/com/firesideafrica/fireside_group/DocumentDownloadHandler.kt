package com.firesideafrica.fireside_group

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** System document picker grants only its chosen URI; no storage permission or cookies. */
class DocumentDownloadHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val REQUEST_CODE = 7241
        const val MAX_BYTES = 25 * 1024 * 1024
        val MIME_TYPES = setOf("application/pdf", "text/csv", "text/plain", "application/zip",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-excel", "image/jpeg", "image/png")
        fun safeName(value: String): String {
            val safe = value.replace(Regex("[^a-zA-Z0-9._ -]"), "_").take(200)
            return if (safe.isBlank() || safe.startsWith(".")) "Fireside-document" else safe
        }
    }
    private data class Pending(val bytes: ByteArray, val result: MethodChannel.Result)
    private var pending: Pending? = null
    private var pickerOutstanding = false
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var generation = 0
    @Volatile private var disposed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> { cancel(); result.success(null) }
            "saveDocument" -> {
                if (disposed || pending != null || pickerOutstanding) { result.error("BUSY", "Finish the current download first.", null); return }
                val bytes = call.argument<ByteArray>("bytes")
                val mime = call.argument<String>("mime")
                val name = call.argument<String>("name")
                if (bytes == null || bytes.isEmpty() || bytes.size > MAX_BYTES ||
                    mime !in MIME_TYPES || name == null || name.length > 200) {
                    result.error("INVALID_DOCUMENT", "Unsupported document size or type.", null); return
                }
                pending = Pending(bytes, result)
                try {
                    pickerOutstanding = true
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mime
                        putExtra(Intent.EXTRA_TITLE, safeName(name))
                    }, REQUEST_CODE)
                } catch (_: Exception) {
                    pickerOutstanding = false
                    pending = null
                    result.error("SAVE_UNAVAILABLE", "No file-saving app is available.", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        if (!pickerOutstanding) return true
        pickerOutstanding = false
        val request = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            pending = null
            request.result.success(false)
            return true
        }
        val lease = generation
        worker.execute {
            var success = false
            try {
                // Cancellation invalidates a still-open system picker before any file IO.
                if (!disposed && generation == lease) {
                    activity.contentResolver.openOutputStream(uri, "w")?.use { output ->
                        output.write(request.bytes)
                        output.flush()
                        success = true
                    }
                }
            } catch (_: Exception) { /* Fixed errors only; no file/URI/secret diagnostics. */ }
            main.post {
                if (!disposed && generation == lease && pending === request) {
                    pending = null
                    if (success) request.result.success(true)
                    else request.result.error("SAVE_FAILED", "File could not be saved. Please retry.", null)
                }
            }
        }
        return true
    }

    fun cancel() {
        generation++
        val old = pending
        pending = null
        old?.result?.success(false)
    }

    fun dispose() {
        cancel()
        disposed = true
        worker.shutdown()
    }
}
