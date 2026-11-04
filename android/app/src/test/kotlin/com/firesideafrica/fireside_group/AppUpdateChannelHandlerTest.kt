package com.firesideafrica.fireside_group

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.content.pm.SigningInfo
import android.net.Uri
import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.*
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@Suppress("DEPRECATION")
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27, 33], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class AppUpdateChannelHandlerTest {
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var context: Context
    private lateinit var pm: PackageManager
    private lateinit var root: File
    private lateinit var apk: File
    private val handlers = mutableListOf<AppUpdateChannelHandler>()
    private val releases = mutableListOf<CountDownLatch>()
    private val replies = mutableListOf<Reply>()
    private val archiveThread = AtomicReference<Thread>()
    private val parses = AtomicInteger()
    private var archiveAction: (() -> Unit)? = null
    private val permission = AtomicBoolean(true)
    private val permissionThread = AtomicReference<Thread>()
    private val launchThread = AtomicReference<Thread>()
    private var launched: Intent? = null
    private var uriFile: File? = null
    private val appId = "com.firesideafrica.firesidegroup"

    @Before fun setup() {
        root = temporary.newFolder("files")
        apk = File(root, "fireside-update-8.apk")
        ZipOutputStream(apk.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("AndroidManifest.xml"))
            zip.write("manifest-fixture".toByteArray())
            zip.closeEntry()
        }
        context = mock(Context::class.java)
        pm = mock(PackageManager::class.java)
        `when`(context.applicationContext).thenReturn(context)
        `when`(context.filesDir).thenReturn(root)
        `when`(context.packageName).thenReturn(appId)
        `when`(context.packageManager).thenReturn(pm)
        `when`(pm.canRequestPackageInstalls()).thenAnswer {
            permissionThread.set(Thread.currentThread())
            permission.get()
        }
        val archiveAnswer = org.mockito.stubbing.Answer<PackageInfo> { invocation ->
            archiveThread.set(Thread.currentThread())
            parses.incrementAndGet()
            // This is the real copied/ZIP-checked snapshot, not a stubbed preflight.
            assertTrue(File(invocation.arguments[0] as String).isFile)
            archiveAction?.invoke()
            info(8)
        }
        val installed = info(7)
        if (Build.VERSION.SDK_INT >= 33) {
            `when`(pm.getPackageArchiveInfo(anyString(), any(PackageManager.PackageInfoFlags::class.java))).thenAnswer(archiveAnswer)
            `when`(pm.getPackageInfo(eq(appId), any(PackageManager.PackageInfoFlags::class.java))).thenReturn(installed)
        } else {
            `when`(pm.getPackageArchiveInfo(anyString(), anyInt())).thenAnswer(archiveAnswer)
            `when`(pm.getPackageInfo(eq(appId), anyInt())).thenReturn(installed)
        }
        doAnswer {
            launchThread.set(Thread.currentThread())
            launched = it.arguments[0] as Intent
            null
        }.`when`(context).startActivity(any(Intent::class.java))
    }

    @After fun cleanup() {
        releases.forEach { it.countDown() }
        // Wait for all real executor work/continuations before the next sandbox test.
        await { replies.all { it.count > 0 } }
        handlers.forEach { it.dispose() }
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun info(version: Long) = PackageInfo().apply {
        packageName = appId
        if (Build.VERSION.SDK_INT >= 28) {
            longVersionCode = version
            signingInfo = mock(SigningInfo::class.java).also {
                `when`(it.apkContentsSigners).thenReturn(arrayOf(Signature("0102")))
            }
        } else {
            versionCode = version.toInt()
            signatures = arrayOf(Signature("0102"))
        }
    }

    private fun handler(app: Context = context, uriFailure: Boolean = false) = AppUpdateChannelHandler(app) { _, file ->
        assertSame(Looper.getMainLooper().thread, Thread.currentThread())
        if (uriFailure) throw IllegalArgumentException("private-file-path")
        uriFile = file
        Uri.parse("content://$appId.fileprovider/verified_updates/${file.name}")
    }.also { handlers.add(it) }

    private inner class Reply : MethodChannel.Result {
        var count = 0
        var code: String? = null
        var value: Any? = null
        override fun success(result: Any?) { record(); value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            record(); code = errorCode
            assertNull(errorDetails)
            assertFalse(errorMessage.orEmpty().contains("secret"))
            assertFalse(errorMessage.orEmpty().contains("private-file-path"))
        }
        override fun notImplemented() { record(); code = "notImplemented" }
        private fun record() {
            assertSame("reply must run on main", Looper.getMainLooper().thread, Thread.currentThread())
            count++
            assertEquals("exactly one terminal reply", 1, count)
        }
    }

    private fun call(handler: AppUpdateChannelHandler, method: String = "installApk", args: Any? = mapOf("path" to apk.path)) =
        Reply().also { replies.add(it); handler.onMethodCall(MethodCall(method, args), it) }

    private fun await(condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (!condition() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(5)
        }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("worker/main continuation timed out", condition())
    }

    private fun blockArchive(): Pair<CountDownLatch, CountDownLatch> {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1).also { releases.add(it) }
        archiveAction = { entered.countDown(); check(release.await(10, TimeUnit.SECONDS)) }
        return entered to release
    }

    private fun snapshots() = File(root, "verified_updates").listFiles().orEmpty()

    @Test fun preflightNeverReadsStorageOnPlatformMainThread() {
        val read = CountDownLatch(1)
        val observed = AtomicReference<Thread>()
        `when`(context.filesDir).thenAnswer {
            observed.set(Thread.currentThread()); read.countDown()
            throw SecurityException("secret")
        }
        val reply = call(handler())
        assertTrue(read.await(5, TimeUnit.SECONDS))
        assertNotSame("preflight must run on a real worker thread", Thread.currentThread(), observed.get())
        await { reply.count == 1 }
        assertEquals("UPDATE_ERROR", reply.code)
    }

    @Test fun malformedAndMissingInputReturnsOneSafeError() {
        val handler = handler()
        for (args in listOf(null, mapOf("path" to 42), mapOf("path" to "/private/session-token.apk"))) {
            val reply = call(handler, args = args)
            await { reply.count == 1 }
            assertNotNull(reply.code)
        }
        verify(context, never()).startActivity(any(Intent::class.java))
    }

    @Test fun unexpectedPlatformExceptionIsSanitized() {
        `when`(context.filesDir).thenThrow(SecurityException("secret-path-token"))
        val reply = call(handler())
        await { reply.count == 1 }
        assertEquals("UPDATE_ERROR", reply.code)
    }

    @Test fun permissionSettingsFailureIsSafe() {
        doThrow(ActivityNotFoundException("secret")).`when`(context).startActivity(any(Intent::class.java))
        val reply = call(handler(), "openInstallPermissionSettings", null)
        assertEquals("UPDATE_ERROR", reply.code)
    }

    @Test fun permissionCheckAndUnknownMethodCompleteOnce() {
        permission.set(false)
        val handler = handler()
        val reply = call(handler, "canInstallPackages", null)
        assertEquals(false, reply.value)
        assertEquals("notImplemented", call(handler, "unknown", null).code)
    }

    @Test fun realSnapshotAndPackageInspectionOffMainInstallerAndReplyOnMain() {
        val (entered, release) = blockArchive()
        val reply = call(handler())
        // A blocked PackageManager on the worker must not block this main-thread heartbeat.
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        assertEquals(0, reply.count)
        assertNotSame(Thread.currentThread(), archiveThread.get())
        release.countDown()
        await { reply.count == 1 }
        assertNull(reply.code)
        assertSame(Thread.currentThread(), permissionThread.get())
        assertSame(Thread.currentThread(), launchThread.get())
        assertEquals(Intent.ACTION_VIEW, launched?.action)
        assertTrue(launched!!.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertArrayEquals(apk.readBytes(), uriFile!!.readBytes())
        assertEquals(1, snapshots().size)
    }

    @Test fun concurrentCallsIncludingRecreatedHandlerAreRejectedWithoutQueuedCopies() {
        val (entered, release) = blockArchive()
        val first = call(handler())
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val other = handler()
        val others = (1..12).map { Reply().also { replies.add(it) } }
        val threads = others.map { reply -> Thread { other.onMethodCall(MethodCall("installApk", mapOf("path" to apk.path)), reply) }.apply { start() } }
        threads.forEach { it.join() }
        shadowOf(Looper.getMainLooper()).idle()
        others.forEach { assertEquals("UPDATE_BUSY", it.code); assertEquals(1, it.count) }
        assertEquals(1, parses.get())
        assertEquals(1, snapshots().size)
        release.countDown()
        await { first.count == 1 }
    }

    @Test fun permissionRevokedDuringInspectionPreventsLaunchAndCleansSnapshot() {
        val (entered, release) = blockArchive()
        val reply = call(handler())
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        permission.set(false)
        release.countDown()
        await { reply.count == 1 }
        assertEquals("INSTALL_PERMISSION_REQUIRED", reply.code)
        assertSame(Thread.currentThread(), permissionThread.get())
        assertTrue(snapshots().isEmpty())
        verify(context, never()).startActivity(any(Intent::class.java))
    }

    @Test fun archiveFailureCompletesOnceCleansAndReleasesAdmission() {
        archiveAction = { throw SecurityException("secret") }
        val handler = handler()
        val failed = call(handler)
        await { failed.count == 1 }
        assertEquals("UPDATE_ERROR", failed.code)
        assertTrue(snapshots().isEmpty())
        archiveAction = null
        val retry = call(handler)
        await { retry.count == 1 }
        assertNull(retry.code)
    }

    @Test fun uriFailureCompletesOnceAndCleansSnapshot() {
        val reply = call(handler(uriFailure = true))
        await { reply.count == 1 }
        assertEquals("UPDATE_ERROR", reply.code)
        assertTrue(snapshots().isEmpty())
        verify(context, never()).startActivity(any(Intent::class.java))
    }

    @Test fun installerFailureCompletesOnceAndCleansSnapshot() {
        doThrow(ActivityNotFoundException("secret")).`when`(context).startActivity(any(Intent::class.java))
        val reply = call(handler())
        await { reply.count == 1 }
        assertEquals("UPDATE_ERROR", reply.code)
        assertTrue(snapshots().isEmpty())
    }

    @Test fun disposeWhileInspectingRepliesOnceNeverLaunchesAndKeepsGlobalAdmissionUntilClean() {
        val (entered, release) = blockArchive()
        val handler = handler()
        val first = call(handler)
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        handler.dispose()
        handler.dispose()
        assertEquals("UPDATE_CANCELLED", first.code)
        assertEquals("UPDATE_CANCELLED", call(handler).code)
        val replacement = handler()
        assertEquals("UPDATE_BUSY", call(replacement).code)
        release.countDown()
        await { snapshots().isEmpty() }
        assertEquals(1, first.count)
        verify(context, never()).startActivity(any(Intent::class.java))
        archiveAction = null
        val retry = call(replacement)
        await { retry.count == 1 }
        assertNull(retry.code)
    }

    @Test fun queuedCompletionAfterDisposeCannotLaunch() {
        val handler = handler()
        val reply = call(handler)
        // Don't idle the main looper until the worker has posted its completion.
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (parses.get() == 0 && System.nanoTime() < deadline) Thread.sleep(5)
        handler.dispose()
        await { snapshots().isEmpty() }
        assertEquals("UPDATE_CANCELLED", reply.code)
        assertEquals(1, reply.count)
        verify(context, never()).startActivity(any(Intent::class.java))
    }

    @Test fun activityIsNotRetainedOrUsedByWorkerOrLaunch() {
        val activity = mock(android.app.Activity::class.java)
        `when`(activity.applicationContext).thenReturn(context)
        val reply = call(handler(activity))
        await { reply.count == 1 }
        verify(activity).applicationContext
        verifyNoMoreInteractions(activity)
        assertNull(reply.code)
    }

    @Test fun backgroundChannelDispatchStillLaunchesSettingsAndRepliesOnMain() {
        val handler = handler()
        val reply = Reply().also { replies.add(it) }
        Thread { handler.onMethodCall(MethodCall("openInstallPermissionSettings", null), reply) }
            .apply { start(); join() }
        assertEquals(0, reply.count)
        await { reply.count == 1 }
        assertNull(reply.code)
        assertSame(Thread.currentThread(), launchThread.get())
        assertEquals(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, launched?.action)
    }

    @Test fun freshPermissionCheckExceptionIsSanitizedAndDoesNotLeakSnapshot() {
        `when`(pm.canRequestPackageInstalls()).thenThrow(SecurityException("secret"))
        val reply = call(handler())
        await { reply.count == 1 }
        assertEquals("UPDATE_ERROR", reply.code)
        assertTrue(snapshots().isEmpty())
        verify(context, never()).startActivity(any(Intent::class.java))
    }

    @Test fun successfulHandoffIsNotDeletedByLaterFailureOrDispose() {
        val handler = handler()
        val first = call(handler)
        await { first.count == 1 }
        val retained = requireNotNull(uriFile)
        val failure = call(handler, args = null)
        await { failure.count == 1 }
        handler.dispose()
        assertTrue(retained.isFile)
        assertArrayEquals(apk.readBytes(), retained.readBytes())
    }
}
