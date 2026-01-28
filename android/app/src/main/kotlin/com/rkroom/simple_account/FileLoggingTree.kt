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

    // 动态控制写入文件的最低级别
    @Volatile var minLogLevel: AppLogLevel = AppLogLevel.DEFAULT

    private val logDirectory: File? by lazy {
        appContext.getExternalFilesDirs(null).firstNotNullOfOrNull {
            it?.takeIf { file -> file.exists() || file.mkdirs() }
        }
    }

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        // 二次拦截：虽然 AppLog.kt 拦截了一次，但 Timber 内部或其他库可能直接调用 Timber.log
        // 这里确保只有符合级别的日志才落盘
        if (priority < minLogLevel.priority) return

        try {
            val storageDir = logDirectory ?: return
            val logFile = File(storageDir, "debug.log")
            val timestamp =
                    SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())

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
                writer.append("$timestamp $priorityTag/${tag ?: "NoTag"}: $message\n")
                t?.let {
                    writer.append(it.stackTraceToString())
                    writer.append("\n")
                }
            }
        } catch (e: Exception) {
            // 这里使用 Android 原生 Log
            Log.e("FileLogger", "写入文件日志失败", e)
        }
    }
}
