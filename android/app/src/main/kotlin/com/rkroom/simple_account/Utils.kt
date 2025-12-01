package com.rkroom.simple_account

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import timber.log.Timber

fun createDownloadUri(context: Context, fileName: String, mimeType: String): Uri? {
    val contentValues =
            ContentValues().apply {
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
    val projection = arrayOf(MediaStore.Downloads.DISPLAY_NAME, MediaStore.Downloads.RELATIVE_PATH)
    val cursor = context.contentResolver.query(uri, projection, null, null, null)

    cursor?.use { c ->
        if (c.moveToFirst()) {
            val displayName =
                    c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME))
            val relativePath =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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

fun ensureCollectorRunning(context: Context): Boolean {
    val collectorComponent = ComponentName(context, MyNotificationListenerService::class.java)
    val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    var collectorRunning = false
    @Suppress("DEPRECATION") val runningServices = manager.getRunningServices(Int.MAX_VALUE)

    if (runningServices.isNullOrEmpty()) return false

    for (service in runningServices) {
        if (service.service == collectorComponent && service.pid == Process.myPid()) {
            collectorRunning = true
            break
        }
    }
    return collectorRunning
}

fun requestNotificationPermission(activity: Activity) {
    val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
    activity.startActivityForResult(intent, MyNotificationListenerService.PERMISSION_REQUEST_CODE)
}

fun convertToPackageConfigItems(rawValue: List<Map<String, Any?>>): List<PackageConfigItem> {
    return rawValue.mapNotNull { map ->
        val packageName = map["packageName"] as? String
        val appName = map["appName"] as? String
        val isAllowed = map["isAllowed"] as? Boolean

        // 验证所有必需字段是否存在且类型正确
        if (packageName != null && appName != null && isAllowed != null) {
            PackageConfigItem(packageName, appName, isAllowed)
        } else {

            null
        }
    }
}

@Serializable
data class BillData(
        val id: String = UUID.randomUUID().toString(),
        val title: String?,
        val content: String?,
        val packageName: String?,
        val postTime: Long?,
        val payment: String?,
        val appName: String?
)

object AppConstants {
    const val UNKNOWN_PACKAGE = "UnknownPackage" // 未知包名常量
    const val UNKNOWN_CLASS = "UnknownClass" // 未知类名常量
}

data class PageIdentifier(val packageName: String, val className: String) {
    override fun toString(): String {
        return "$packageName/$className"
    }
}

object AppUtils {

    private val appNameCache = ConcurrentHashMap<String, String>()

    /**
     * 根据包名获取应用程序的名称
     *
     * @param context 上下文对象，用于获取 PackageManager
     * @param packageName 应用程序的包名
     * @return 应用程序的名称，如果找不到则返回包名本身
     */
    fun getAppName(context: Context, packageName: String?): String {
        if (packageName.isNullOrBlank()) {
            return "Unknown" // 对空或空白的包名进行处理
        }

        return appNameCache.computeIfAbsent(packageName) { key ->
            try {
                val pm = context.applicationContext.packageManager
                val appInfo = pm.getApplicationInfo(key, 0)
                pm.getApplicationLabel(appInfo).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                key
            }
        }
    }
}

object BillingRepository {

    private val repositoryScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val json = Json { ignoreUnknownKeys = true }

    fun saveBill(context: Context, billData: BillData) {
        repositoryScope.launch {
            try {
                BillDataStoreManager.getInstance(context).addOrUpdateBill(billData)
            } catch (e: Exception) {
                Timber.e(e, "BillingRepository: 保存账单数据失败。")
            }
        }
    }
}
