package com.firesideafrica.fireside_group

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.ZipFile

internal class ApkPreflightException(val code: String, message: String) : Exception(message)

/** Fail closed before any URI grant. Only the checked private snapshot may be shared. */
internal class ApkInstallPreflight(
    private val filesDir: File,
    private val packageManager: PackageManager,
    private val packageName: String,
) {
    fun prepare(arguments: Any?): File {
        val args = arguments as? Map<*, *> ?: refuse("INVALID_PATH", "APK path was not supplied")
        val path = args["path"] as? String ?: refuse("INVALID_PATH", "APK path was not supplied")
        val expectedSize = optionalLong(args, "size")
        val expectedVersion = optionalLong(args, "versionCode")
        val expectedHash = optionalDigest(args, "sha256")
        val expectedSigner = optionalDigest(args, "signerSha256")
        val root = filesDir.canonicalFile
        val source = File(path)
        // Permit Android's own filesDir alias (/data/user/0 versus /data/data),
        // but no caller-selected parent, dot segments or leaf symlink.
        if (!source.isAbsolute ||
            (source.parentFile != filesDir.absoluteFile && source.parentFile != root) ||
            source.canonicalFile != File(root, source.name) ||
            !Regex("fireside-update-[1-9][0-9]*\\.apk").matches(source.name)) {
            refuse("INVALID_PATH", "APK must be a final download in private updater storage")
        }
        if (!source.isFile || source.length() !in 1..MAX_APK_BYTES) {
            refuse("INVALID_APK", "APK file is missing, empty or too large")
        }
        val directory = File(root, "verified_updates")
        if (directory.canonicalFile != directory || (!directory.isDirectory && !directory.mkdir())) {
            refuse("INVALID_PATH", "Private updater storage is unavailable")
        }
        val snapshot = File.createTempFile("verified-", ".apk", directory)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            source.inputStream().use { input ->
                snapshot.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > MAX_APK_BYTES) refuse("INVALID_APK", "APK file is too large")
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (copied == 0L || copied != source.length() || (expectedSize != null && copied != expectedSize) ||
                (expectedHash != null && hex(digest.digest()) != expectedHash)) {
                refuse("INVALID_APK", "APK download integrity check failed")
            }
            if (!snapshot.setReadOnly()) refuse("INVALID_APK", "APK snapshot could not be protected")
            validateZip(snapshot)
            val archive = archiveInfo(snapshot) ?: refuse("INVALID_APK", "APK archive could not be parsed")
            if (archive.packageName != packageName) refuse("PACKAGE_MISMATCH", "APK is not an update for this app")
            val installed = installedInfo()
            if (installed.packageName != packageName) refuse("PACKAGE_MISMATCH", "Installed app identity is unavailable")
            if (version(archive) <= version(installed)) refuse("VERSION_NOT_NEWER", "APK version must be newer than the installed app")
            if (expectedVersion != null && version(archive) != expectedVersion) {
                refuse("VERSION_MISMATCH", "APK version does not match the expected update")
            }
            val archiveSigners = currentSigners(archive)
            val installedSigners = currentSigners(installed)
            // Do not accept history/overlap: an ancestor alone does not establish update capability.
            if (archiveSigners.isEmpty() || installedSigners.isEmpty() || archiveSigners != installedSigners ||
                (expectedSigner != null && archiveSigners != setOf(expectedSigner))) {
                refuse("SIGNATURE_MISMATCH", "APK signing identity does not match the installed app")
            }
            return snapshot
        } catch (error: Exception) {
            snapshot.delete()
            throw error
        }
    }

    private fun validateZip(file: File) {
        try {
            ZipFile(file).use { zip ->
                val manifest = zip.getEntry("AndroidManifest.xml")
                if (manifest == null || manifest.isDirectory || manifest.size <= 0) {
                    refuse("INVALID_APK", "APK manifest is missing")
                }
                val entries = zip.entries()
                val names = HashSet<String>()
                var expanded = 0L
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (!names.add(entry.name) || names.size > 100000) refuse("INVALID_APK", "APK archive is malformed")
                    if (entry.isDirectory) continue
                    val crc = CRC32()
                    var size = 0L
                    zip.getInputStream(entry).use { input ->
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            size += count
                            expanded += count
                            if (expanded > MAX_EXPANDED_BYTES) refuse("INVALID_APK", "APK archive is too large")
                            crc.update(buffer, 0, count)
                        }
                    }
                    if (size != entry.size || crc.value != entry.crc) refuse("INVALID_APK", "APK archive is incomplete or corrupt")
                }
            }
        } catch (error: ApkPreflightException) {
            throw error
        } catch (_: Exception) {
            refuse("INVALID_APK", "APK archive is incomplete or malformed")
        }
    }

    private val signingFlags: Int
        @Suppress("DEPRECATION")
        get() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun archiveInfo(file: File): PackageInfo? = if (Build.VERSION.SDK_INT >= 33) {
        packageManager.getPackageArchiveInfo(file.path, PackageManager.PackageInfoFlags.of(signingFlags.toLong()))
    } else {
        packageManager.getPackageArchiveInfo(file.path, signingFlags)
    }

    @Suppress("DEPRECATION")
    private fun installedInfo(): PackageInfo = if (Build.VERSION.SDK_INT >= 33) {
        packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(signingFlags.toLong()))
    } else {
        packageManager.getPackageInfo(packageName, signingFlags)
    }

    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun currentSigners(info: PackageInfo): Set<String> {
        val signers = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signers.orEmpty().map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toSet()
    }

    private fun optionalLong(args: Map<*, *>, key: String): Long? {
        val value = args[key] ?: return null
        val number = when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> refuse("INVALID_ARGUMENT", "Update metadata has an invalid numeric field")
        }
        if (number <= 0) refuse("INVALID_ARGUMENT", "Update metadata has an invalid numeric field")
        return number
    }

    private fun optionalDigest(args: Map<*, *>, key: String): String? {
        val value = args[key] ?: return null
        if (value !is String || !Regex("[a-fA-F0-9]{64}").matches(value)) {
            refuse("INVALID_ARGUMENT", "Update metadata has an invalid fingerprint")
        }
        return value.lowercase()
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
    private fun refuse(code: String, message: String): Nothing = throw ApkPreflightException(code, message)

    private companion object {
        const val MAX_APK_BYTES = 536870912L
        const val MAX_EXPANDED_BYTES = 1073741824L
    }
}
