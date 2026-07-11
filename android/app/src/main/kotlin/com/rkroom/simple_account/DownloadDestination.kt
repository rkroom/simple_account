package com.rkroom.simple_account

import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

internal enum class DownloadStorageStrategy {
    LEGACY_FILE,
    MEDIA_STORE,
}

internal fun downloadStorageStrategy(sdkInt: Int): DownloadStorageStrategy =
        if (sdkInt >= 29) {
            DownloadStorageStrategy.MEDIA_STORE
        } else {
            DownloadStorageStrategy.LEGACY_FILE
        }

internal data class DownloadDestination(
        val outputStream: OutputStream,
        val displayPath: String,
)

internal fun createLegacyDownloadDestination(
        downloadDirectory: File,
        fileName: String,
): DownloadDestination? {
    val safeFileName = File(fileName).name
    if (safeFileName.isEmpty()) return null
    if (!downloadDirectory.exists() && !downloadDirectory.mkdirs()) return null
    if (!downloadDirectory.isDirectory) return null

    val destinationFile = File(downloadDirectory, safeFileName)
    return DownloadDestination(
            outputStream = FileOutputStream(destinationFile),
            displayPath = destinationFile.absolutePath,
    )
}
