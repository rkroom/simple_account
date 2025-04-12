package com.rkroom.simple_account

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore

fun createDownloadUri(context: Context, fileName: String, mimeType: String): Uri? {
    val contentValues = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
        put(MediaStore.Downloads.MIME_TYPE, mimeType)
        put(MediaStore.Downloads.DATE_ADDED, System.currentTimeMillis() / 1000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
        }
    }
    return context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
}

fun getDownloadFilePath(context: Context, uri: Uri, defaultFileName: String): String {
    val projection = arrayOf(
        MediaStore.Downloads.DISPLAY_NAME,
        MediaStore.Downloads.RELATIVE_PATH
    )
    val cursor = context.contentResolver.query(uri, projection, null, null, null)
    
    cursor?.use { c ->
        if (c.moveToFirst()) {
            val displayName = c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME))
            val relativePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.RELATIVE_PATH))
                    ?: Environment.DIRECTORY_DOWNLOADS
            } else {
                Environment.DIRECTORY_DOWNLOADS
            }
            val cleanPath = relativePath.removeSuffix("/").replace("//", "/")
            return "$cleanPath/$displayName"
        }
    }
    return "${Environment.DIRECTORY_DOWNLOADS}/$defaultFileName"
}