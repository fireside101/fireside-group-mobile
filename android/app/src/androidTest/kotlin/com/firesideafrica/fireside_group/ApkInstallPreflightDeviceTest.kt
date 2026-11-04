package com.firesideafrica.fireside_group

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Runs against the device PackageManager, not Robolectric's archive shadow. */
@RunWith(AndroidJUnit4::class)
class ApkInstallPreflightDeviceTest {
    private fun rejected(block: () -> Unit): ApkPreflightException {
        try {
            block()
        } catch (error: ApkPreflightException) {
            return error
        }
        throw AssertionError("Expected native APK preflight refusal")
    }
    @Test fun installedApkIsParsedButRefusedAsNonIncreasingUpdate() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val source = File(context.filesDir, "fireside-update-900000000.apk")
        try {
            File(context.applicationInfo.sourceDir).copyTo(source, overwrite = true)
            val error = rejected {
                ApkInstallPreflight(context.filesDir, context.packageManager, context.packageName)
                    .prepare(mapOf("path" to source.path))
            }
            assertEquals("VERSION_NOT_NEWER", error.code)
        } finally {
            source.delete()
        }
    }

    @Test fun truncatedInstalledApkNeverPassesPreflight() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val source = File(context.filesDir, "fireside-update-900000000.apk")
        try {
            File(context.applicationInfo.sourceDir).inputStream().use { input ->
                val buffer = ByteArray(1024)
                val count = input.read(buffer)
                source.outputStream().use { output -> output.write(buffer, 0, count) }
            }
            val error = rejected {
                ApkInstallPreflight(context.filesDir, context.packageManager, context.packageName)
                    .prepare(mapOf("path" to source.path))
            }
            assertEquals("INVALID_APK", error.code)
        } finally {
            source.delete()
        }
    }
}
