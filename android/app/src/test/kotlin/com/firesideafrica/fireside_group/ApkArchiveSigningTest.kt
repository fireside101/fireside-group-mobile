package com.firesideafrica.fireside_group

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.*
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/** Execute Android's actual archive parser, not ShadowPackageManager's canned archive lookup. */
@Suppress("DEPRECATION")
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 33], manifest = Config.NONE, shadows = [ApkArchiveSigningTest.JvmFileDataSource::class, ApkArchiveSigningTest.FrameworkSigningInfo::class])
class ApkArchiveSigningTest {
    // Disable ShadowSigningInfo's synthetic signer fields; retain the framework implementation.
    @org.robolectric.annotation.Implements(android.content.pm.SigningInfo::class)
    class FrameworkSigningInfo

    /** Android's DirectByteBuffer constructor is absent on JDK 21. Replace only file I/O;
     * Android's parser, certificate collection and cryptographic verification remain real. */
    @org.robolectric.annotation.Implements(className = "android.util.apk.MemoryMappedFileDataSource", isInAndroidSdk = false)
    class JvmFileDataSource {
        @org.robolectric.annotation.RealObject lateinit var source: Any
        private var stream: java.io.FileInputStream? = null

        @org.robolectric.annotation.Implementation
        fun feedIntoDataDigester(@org.robolectric.annotation.ClassName("android.util.apk.DataDigester") digester: Any,
                                 offset: Long, size: Int) {
            val fd = org.robolectric.util.ReflectionHelpers.getField<java.io.FileDescriptor>(source, "mFd")
            val position = org.robolectric.util.ReflectionHelpers.getField<Long>(source, "mFilePosition") + offset
            val input = stream ?: java.io.FileInputStream(fd).also { stream = it }
            val buffer = java.nio.ByteBuffer.allocate(size)
            while (buffer.hasRemaining()) {
                val read = input.channel.read(buffer, position + buffer.position())
                check(read > 0) { "Unexpected EOF in APK digest input" }
            }
            buffer.flip()
            val method = Class.forName("android.util.apk.DataDigester").getDeclaredMethod("consume", java.nio.ByteBuffer::class.java)
            method.isAccessible = true
            method.invoke(digester, buffer)
        }
    }

    @get:Rule val temporary = TemporaryFolder()
    private val appId = "com.firesideafrica.firesidegroup"
    private val completeFlags = PackageManager.GET_SIGNATURES or PackageManager.GET_SIGNING_CERTIFICATES

    private fun parser(): PackageManager {
        val pm = mock(PackageManager::class.java)
        if (Build.VERSION.SDK_INT >= 33) {
            `when`(pm.getPackageArchiveInfo(anyString(), any(PackageManager.PackageInfoFlags::class.java))).thenAnswer {
                realParse(it.getArgument(0), it.getArgument<PackageManager.PackageInfoFlags>(1).value.toInt())
            }
        } else {
            `when`(pm.getPackageArchiveInfo(anyString(), anyInt())).thenAnswer {
                realParse(it.getArgument(0), it.getArgument(1))
            }
        }
        return pm
    }

    private fun realParse(path: String, flags: Int): PackageInfo? {
        val pm = org.robolectric.RuntimeEnvironment.getApplication().packageManager
        return if (Build.VERSION.SDK_INT >= 33) {
            org.robolectric.shadow.api.Shadow.directlyOn(pm, PackageManager::class.java, "getPackageArchiveInfo",
                org.robolectric.util.ReflectionHelpers.ClassParameter.from(String::class.java, path),
                org.robolectric.util.ReflectionHelpers.ClassParameter.from(PackageManager.PackageInfoFlags::class.java,
                    PackageManager.PackageInfoFlags.of(flags.toLong())))
        } else {
            org.robolectric.shadow.api.Shadow.directlyOn(pm, PackageManager::class.java, "getPackageArchiveInfo",
                org.robolectric.util.ReflectionHelpers.ClassParameter.from(String::class.java, path),
                org.robolectric.util.ReflectionHelpers.ClassParameter.from(Int::class.javaPrimitiveType, flags))
        }
    }

    private fun parse(pm: PackageManager, file: File, flags: Int): PackageInfo? =
        if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageArchiveInfo(file.path, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else pm.getPackageArchiveInfo(file.path, flags)

    private fun fixture(): File = temporary.newFile("fixture.apk").also { file ->
        val retained = System.getenv("APK_SIGNING_UPDATE")
        if (retained != null) File(retained).copyTo(file, overwrite = true)
        else requireNotNull(javaClass.getResourceAsStream("/same-signer-update.apk")).use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
    }

    @Test fun frameworkRequiresLegacyCollectionFlagForModernSigningInfo() {
        val pm = parser()
        val source = fixture()
        val modernOnly = requireNotNull(parse(pm, source, PackageManager.GET_SIGNING_CERTIFICATES))
        assertNull("Android 28/33 does not collect archive certs with modern-only flags", modernOnly.signingInfo)
        val complete = requireNotNull(parse(pm, source, completeFlags))
        assertFalse(requireNotNull(complete.signingInfo).apkContentsSigners.isEmpty())
    }

    @Test fun realCertificateVerificationRejectsTamperedSignedFixture() {
        val source = temporary.newFile("tampered.apk")
        val bytes = requireNotNull(javaClass.getResourceAsStream("/same-signer-update.apk")).use { it.readBytes() }
        val marker = "Disposable Android Test Fixture".toByteArray()
        val offsets = (0..bytes.size - marker.size).filter { start ->
            marker.indices.all { bytes[start + it] == marker[it] }
        }
        assertTrue(offsets.isNotEmpty())
        // Corrupt both v2 and v3 certificate blocks, not an unused lower-scheme record only.
        offsets.forEach { bytes[it] = (bytes[it].toInt() xor 1).toByte() }
        source.writeBytes(bytes)
        val pm = parser()
        // Manifest parsing still works; requesting actual certificate collection detects tampering.
        assertNotNull(parse(pm, source, PackageManager.GET_SIGNING_CERTIFICATES))
        assertNull(parse(pm, source, completeFlags))
    }

    @Test fun preflightAcceptsActualSignedArchiveWithSameInstalledIdentity() {
        val pm = parser()
        val root = temporary.newFolder("files")
        val source = fixture().copyTo(File(root, "fireside-update-10.apk"))
        val baseline = System.getenv("APK_SIGNING_BASELINE")
        val installed = if (baseline != null) requireNotNull(parse(pm, File(baseline), completeFlags))
            else requireNotNull(parse(pm, source, completeFlags)).apply { longVersionCode = 9 }
        assertFalse(requireNotNull(installed.signingInfo).apkContentsSigners.isEmpty())
        if (Build.VERSION.SDK_INT >= 33) {
            doReturn(installed).`when`(pm).getPackageInfo(eq(appId), any(PackageManager.PackageInfoFlags::class.java))
        } else {
            doReturn(installed).`when`(pm).getPackageInfo(eq(appId), anyInt())
        }
        assertTrue(ApkInstallPreflight(root, pm, appId).prepare(mapOf("path" to source.path)).isFile)
    }
}
