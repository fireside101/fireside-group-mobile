package com.firesideafrica.fireside_group

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.content.pm.SigningInfo
import android.os.Build
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.*
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@Suppress("DEPRECATION")
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27, 28, 33], manifest = Config.NONE)
class ApkInstallPreflightTest {
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var root: File
    private lateinit var pm: PackageManager
    private lateinit var candidate: PackageInfo
    private lateinit var installed: PackageInfo
    private lateinit var preflight: ApkInstallPreflight
    private val appId = "com.firesideafrica.firesidegroup"

    @Before fun setup() {
        root = temporary.newFolder("files")
        pm = mock(PackageManager::class.java)
        installed = info(appId, 7, arrayOf(Signature("0102")))
        candidate = info(appId, 8, arrayOf(Signature("0102")))
        if (Build.VERSION.SDK_INT >= 33) {
            `when`(pm.getPackageArchiveInfo(anyString(), any(PackageManager.PackageInfoFlags::class.java))).thenAnswer { candidate }
            `when`(pm.getPackageInfo(eq(appId), any(PackageManager.PackageInfoFlags::class.java))).thenAnswer { installed }
        } else {
            `when`(pm.getPackageArchiveInfo(anyString(), anyInt())).thenAnswer { candidate }
            `when`(pm.getPackageInfo(eq(appId), anyInt())).thenAnswer { installed }
        }
        preflight = ApkInstallPreflight(root, pm, appId)
    }

    private fun info(id: String, version: Long, signers: Array<Signature>): PackageInfo = PackageInfo().apply {
        packageName = id
        if (Build.VERSION.SDK_INT >= 28) {
            longVersionCode = version
            signingInfo = mock(SigningInfo::class.java).also {
                `when`(it.apkContentsSigners).thenReturn(signers)
            }
        } else {
            @Suppress("DEPRECATION")
            versionCode = version.toInt()
            @Suppress("DEPRECATION")
            signatures = signers
        }
    }

    private fun apk(name: String = "fireside-update-8.apk"): File = File(root, name).also { file ->
        ZipOutputStream(file.outputStream()).use { zip ->
            for (name in listOf("AndroidManifest.xml", "classes.dex")) {
                zip.putNextEntry(ZipEntry(name))
                zip.write("fixture-$name".toByteArray())
                zip.closeEntry()
            }
        }
    }

    private fun reject(code: String, path: String?, extra: Map<String, Any?> = emptyMap()) {
        val error = assertThrows(ApkPreflightException::class.java) {
            preflight.prepare(mapOf("path" to path) + extra)
        }
        assertEquals(code, error.code)
        assertTrue(File(root, "verified_updates").listFiles().orEmpty().isEmpty())
    }

    @Test fun acceptsNewerSameIdentityAndUsesPrivateSnapshot() {
        val source = apk()
        val accepted = preflight.prepare(mapOf("path" to source.path))
        assertEquals(File(root, "verified_updates").canonicalFile, accepted.parentFile)
        assertArrayEquals(source.readBytes(), accepted.readBytes())
        source.writeText("changed after preflight")
        assertTrue(accepted.length() > source.length())
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        if (Build.VERSION.SDK_INT >= 33) {
            verify(pm).getPackageArchiveInfo(eq(accepted.path), any(PackageManager.PackageInfoFlags::class.java))
        } else {
            verify(pm).getPackageArchiveInfo(accepted.path, flags)
        }
    }

    @Test fun acceptsOnlyTheContextProvidedStorageAlias() {
        apk()
        val alias = File(temporary.root, "context-files-alias")
        Files.createSymbolicLink(alias.toPath(), root.toPath())
        val aliased = ApkInstallPreflight(alias, pm, appId)
        val accepted = aliased.prepare(mapOf("path" to File(alias, "fireside-update-8.apk").path))
        assertTrue(accepted.isFile)
        assertTrue(accepted.delete())
        // An arbitrary alias supplied by the caller is not the trusted context alias.
        reject("INVALID_PATH", File(alias, "fireside-update-8.apk").path)
    }

    @Test fun rejectsMissingPathAndMalformedArguments() {
        reject("INVALID_PATH", null)
        assertThrows(ApkPreflightException::class.java) { preflight.prepare(mapOf("path" to 42)) }
        assertThrows(ApkPreflightException::class.java) { preflight.prepare("not a map") }
    }
    @Test fun rejectsSiblingPrefixTraversalAndSymlink() {
        val outside = File(temporary.newFolder("files-other"), "fireside-update-8.apk").apply { writeText("bad") }
        reject("INVALID_PATH", outside.path)
        reject("INVALID_PATH", File(root, "../${outside.parentFile!!.name}/${outside.name}").path)
        Files.createSymbolicLink(File(root, "fireside-update-8.apk").toPath(), outside.toPath())
        reject("INVALID_PATH", File(root, "fireside-update-8.apk").path)
        verifyNoInteractions(pm)
    }
    @Test fun rejectsMissingEmptyPartAndArbitraryPrivateFile() {
        reject("INVALID_APK", File(root, "fireside-update-8.apk").path)
        reject("INVALID_APK", File(root, "fireside-update-8.apk").apply { writeText("") }.path)
        reject("INVALID_PATH", apk("fireside-update-8.apk.part").path)
        reject("INVALID_PATH", apk("session.apk").path)
    }
    @Test fun rejectsMalformedAndTruncatedArchives() {
        val source = apk().apply { writeText("not an apk") }
        reject("INVALID_APK", source.path)
        apk()
        val bytes = source.readBytes()
        source.writeBytes(bytes.copyOf(bytes.size / 2))
        reject("INVALID_APK", source.path)
    }
    @Test fun rejectsPackageManagerParseFailure() {
        val source = apk()
        if (Build.VERSION.SDK_INT >= 33) {
            `when`(pm.getPackageArchiveInfo(anyString(), any(PackageManager.PackageInfoFlags::class.java))).thenReturn(null)
        } else {
            `when`(pm.getPackageArchiveInfo(anyString(), anyInt())).thenReturn(null)
        }
        reject("INVALID_APK", source.path)
    }
    @Test fun rejectsWrongPackage() {
        candidate.packageName = "another.app"
        reject("PACKAGE_MISMATCH", apk().path)
    }
    @Test fun rejectsEqualAndLowerVersion() {
        candidate = info(appId, 7, arrayOf(Signature("0102")))
        reject("VERSION_NOT_NEWER", apk().path)
        candidate = info(appId, 6, arrayOf(Signature("0102")))
        reject("VERSION_NOT_NEWER", apk().path)
    }
    @Test fun rejectsDifferentMissingOrSubsetSigners() {
        candidate = info(appId, 8, arrayOf(Signature("0304")))
        reject("SIGNATURE_MISMATCH", apk().path)
        candidate = info(appId, 8, emptyArray())
        reject("SIGNATURE_MISMATCH", apk().path)
        installed = info(appId, 7, arrayOf(Signature("0102"), Signature("0304")))
        candidate = info(appId, 8, arrayOf(Signature("0102")))
        reject("SIGNATURE_MISMATCH", apk().path)
    }
    @Test fun acceptsExactMultipleSignerSetRegardlessOfOrder() {
        installed = info(appId, 7, arrayOf(Signature("0102"), Signature("0304")))
        candidate = info(appId, 8, arrayOf(Signature("0304"), Signature("0102")))
        assertTrue(preflight.prepare(mapOf("path" to apk().path)).isFile)
    }
    @Test fun checksOptionalExpectedMetadataButNeverTrustsItForIdentity() {
        val source = apk()
        reject("INVALID_APK", source.path, mapOf("size" to source.length() + 1))
        reject("INVALID_APK", source.path, mapOf("sha256" to "0".repeat(64)))
        reject("VERSION_MISMATCH", source.path, mapOf("versionCode" to 9))
        reject("SIGNATURE_MISMATCH", source.path, mapOf("signerSha256" to "0".repeat(64)))
        reject("INVALID_ARGUMENT", source.path, mapOf("size" to "42"))
    }
    @Test fun rejectsCorruptZipEntryAndMissingManifest() {
        val source = apk()
        val bytes = source.readBytes()
        // Damage the first compressed entry without changing its central-directory CRC.
        val nameLength = (bytes[26].toInt() and 255) + ((bytes[27].toInt() and 255) shl 8)
        val offset = 30 + nameLength
        bytes[offset] = (bytes[offset].toInt() xor 127).toByte()
        source.writeBytes(bytes)
        reject("INVALID_APK", source.path)
        ZipOutputStream(source.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("classes.dex"))
            zip.write(byteArrayOf(1))
            zip.closeEntry()
        }
        reject("INVALID_APK", source.path)
    }

    @Test fun acceptsMatchingExpectedMetadata() {
        val source = apk()
        val hash = java.security.MessageDigest.getInstance("SHA-256")
            .digest(source.readBytes()).joinToString("") { "%02x".format(it) }
        val signer = java.security.MessageDigest.getInstance("SHA-256")
            .digest(Signature("0102").toByteArray()).joinToString("") { "%02x".format(it) }
        assertTrue(preflight.prepare(mapOf("path" to source.path, "size" to source.length(),
            "versionCode" to 8L, "sha256" to hash, "signerSha256" to signer)).isFile)
    }

    @Test fun rejectsUnknownSigningIdentity() {
        if (Build.VERSION.SDK_INT >= 28) candidate.signingInfo = null
        else candidate.signatures = null
        reject("SIGNATURE_MISMATCH", apk().path)
    }

    @Test fun rejectsMetadataTypesAndInvalidFingerprints() {
        val source = apk()
        for (extra in listOf(mapOf("sha256" to "bad"), mapOf("size" to 1.0),
            mapOf("versionCode" to -1), mapOf("signerSha256" to 42), mapOf("size" to true))) {
            reject("INVALID_ARGUMENT", source.path, extra)
        }
    }

    @Test fun rejectsRedirectedSnapshotDirectory() {
        Files.createSymbolicLink(File(root, "verified_updates").toPath(), temporary.newFolder("outside").toPath())
        reject("INVALID_PATH", apk().path)
    }
    @Test fun usesLongVersionCodesOnModernAndroid() {
        if (Build.VERSION.SDK_INT < 28) return
        installed = info(appId, 0x100000007L, arrayOf(Signature("0102")))
        candidate = info(appId, 8, arrayOf(Signature("0102")))
        reject("VERSION_NOT_NEWER", apk().path)
    }
}
