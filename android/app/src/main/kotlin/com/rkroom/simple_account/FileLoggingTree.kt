package com.rkroom.simple_account

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import timber.log.Timber

class FileLoggingTree(context: Context) : Timber.Tree() {

    private val appContext = context.applicationContext

    private val logDirectory: File? by lazy {
        appContext.getExternalFilesDirs(null).firstNotNullOfOrNull {
            it?.takeIf { file -> file.exists() || file.mkdirs() }
        }
    }

    companion object {
        private const val LOG_FILE_NAME = "debug.log"
        private const val DATE_FORMAT = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        try {
            val storageDir = logDirectory ?: return

            val logFile = File(storageDir, LOG_FILE_NAME)
            val logTimeStamp = SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).format(Date())

            val priorityTag =
                    when (priority) {
                        Log.VERBOSE -> "V"
                        Log.DEBUG -> "D"
                        Log.INFO -> "I"
                        Log.WARN -> "W"
                        Log.ERROR -> "E"
                        Log.ASSERT -> "A"
                        else -> "?"
                    }

            FileWriter(logFile, true).use { writer ->
                writer.append("$logTimeStamp $priorityTag/${tag ?: "NoTag"}: $message\n")
                t?.let {
                    writer.append(it.stackTraceToString())
                    writer.append("\n")
                }
            }
        } catch (e: Exception) {
            Log.e("FileLogger", "Error while logging to file", e)
        }
    }
}
