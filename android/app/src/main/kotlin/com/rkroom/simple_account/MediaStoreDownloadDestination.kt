package com.rkroom.simple_account

import android.annotation.TargetApi
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.IOException
import java.io.OutputStream

@TargetApi(Build.VERSION_CODES.Q)
internal fun createMediaStoreDownloadDestination(
        context: Context,
        fileName: String,
        mimeType: String,
): DownloadDestination? {
    val contentValues =
            ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.DATE_ADDED, System.currentTimeMillis() / 1000)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
    val resolver = context.contentResolver
    val uri =
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                    ?: return null
    return try {
        val displayPath = getDownloadFilePath(context, uri, fileName)
        val outputStream: OutputStream =
                resolver.openOutputStream(uri)
                        ?: throw IOException("Cannot open output stream")
        DownloadDestination(
                outputStream = outputStream,
                displayPath = displayPath,
        )
    } catch (error: Exception) {
        resolver.delete(uri, null, null)
        throw error
    }
}

@TargetApi(Build.VERSION_CODES.Q)
private fun getDownloadFilePath(context: Context, uri: Uri, defaultFileName: String): String {
    val projection = arrayOf(MediaStore.Downloads.DISPLAY_NAME, MediaStore.Downloads.RELATIVE_PATH)
    val cursor = context.contentResolver.query(uri, projection, null, null, null)

    cursor?.use { c ->
        if (c.moveToFirst()) {
            val displayName =
                    c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME))
            val relativePath =
                    c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.RELATIVE_PATH))
                            ?: Environment.DIRECTORY_DOWNLOADS
            val cleanPath = relativePath.removeSuffix("/").replace("//", "/")
            return "$cleanPath/$displayName"
        }
    }
    return "${Environment.DIRECTORY_DOWNLOADS}/$defaultFileName"
}
