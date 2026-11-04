package com.firesideafrica.fireside_group

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class AppUpdateChannelHandler(
    context: Context,
    private val snapshotUri: (Context, File) -> Uri = { app, file ->
        FileProvider.getUriForFile(app, "${app.packageName}.fileprovider", file)
    },
) : MethodChannel.MethodCallHandler {
    // Never retain the Activity in a worker, posted continuation or URI factory.
    private val context = requireNotNull(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())
    // These fields are confined to the main looper, including disposal.
    private var disposed = false
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) = onMain {
        if (disposed) {
            cancelled(result)
            return@onMain
        }
        try {
            when (call.method) {
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:${context.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                    }
                    result.success(null)
                }
                "installApk" -> install(call.arguments, result)
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            fail(result, error)
        }
    }

    private fun install(arguments: Any?, result: MethodChannel.Result) {
        // Process-wide admission remains held through the main-thread launch/cleanup.
        // A recreated Activity must not overlap the old handler's preflight.
        if (!installBusy.compareAndSet(false, true)) {
            result.error("UPDATE_BUSY", "An Android update operation is already in progress", null)
            return
        }
        pending = result
        try {
            worker.execute {
                var snapshot: File? = null
                var failure: Exception? = null
                try {
                    snapshot = ApkInstallPreflight(context.filesDir, context.packageManager, context.packageName)
                        .prepare(arguments)
                } catch (error: Exception) {
                    failure = error
                }
                val prepared = snapshot
                val error = failure
                main.post {
                    try {
                        if (disposed) {
                            // No installer has received this snapshot, so deletion is safe.
                            runCatching { prepared?.delete() }
                        } else if (error != null) {
                            fail(result, error)
                        } else {
                            var launched = false
                            try {
                                // Permission can change while the worker is inspecting the APK.
                                // Check afresh on the main thread immediately before URI grant/launch.
                                if (!canInstallPackages()) {
                                    throw ApkPreflightException("INSTALL_PERMISSION_REQUIRED", "Allow app installations in Android settings first")
                                }
                                val uri = snapshotUri(context, requireNotNull(prepared))
                                context.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                })
                                launched = true
                                result.success(null)
                            } catch (launchError: Exception) {
                                fail(result, launchError)
                            } finally {
                                // Never delete a handed-off APK: external installation is asynchronous.
                                if (!launched) runCatching { prepared?.delete() }
                            }
                        }
                    } finally {
                        pending = null
                        installBusy.set(false)
                    }
                }
            }
        } catch (error: Exception) {
            pending = null
            installBusy.set(false)
            fail(result, error)
        }
    }

    /** Detach before engine/Activity teardown. Running work owns application context only. */
    fun dispose() = onMain {
        disposed = true
        pending?.let { cancelled(it) }
        pending = null
        // Do not release admission or interrupt a copy: its continuation must clean up first.
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post { action() }
    }

    private fun cancelled(result: MethodChannel.Result) =
        result.error("UPDATE_CANCELLED", "The Android update operation was cancelled", null)

    private fun fail(result: MethodChannel.Result, error: Exception) {
        if (error is ApkPreflightException) result.error(error.code, error.message, null)
        else result.error("UPDATE_ERROR", "The Android update operation could not be completed", null)
    }

    private fun canInstallPackages(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
        context.packageManager.canRequestPackageInstalls()

    private companion object {
        val installBusy = AtomicBoolean(false)
        // Bounded, serialized and never CallerRunsPolicy (which would block Flutter again).
        // Shared across handler lifetimes; idle threads expire, never reference an Activity.
        val worker = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue(1),
            { runnable -> Thread(runnable, "apk-preflight").apply { isDaemon = true } },
            ThreadPoolExecutor.AbortPolicy()).apply { allowCoreThreadTimeOut(true) }
    }
}
