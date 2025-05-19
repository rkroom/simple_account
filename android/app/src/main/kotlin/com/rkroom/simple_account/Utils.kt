package com.rkroom.simple_account

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import kotlinx.serialization.Serializable

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
data class billData(
        val title: String?,
        val content: String?,
        val packageName: String?,
        val postTime: Long?,
        val payment: String?
)

object AppConstants {
    const val UNKNOWN_PACKAGE = "UnknownPackage" // 未知包名常量
    const val UNKNOWN_CLASS = "UnknownClass" // 未知类名常量

    const val PACKAGE_JD = "com.jingdong.app.mall"
    const val PACKAGE_ALIPAY = "com.eg.android.AlipayGphone"
    const val PACKAGE_WECHAT = "com.tencent.mm"

    const val KEYWORD_PAYMENT_SUCCESS = "支付成功"
    const val KEYWORD_TRANSACTION_METHOD_ALIPAY_1 = "交易方式" // 支付宝特定关键字
    const val KEYWORD_TRANSACTION_METHOD_ALIPAY_2 = "付款方式"
    const val CURRENCY_SYMBOL_CNY = "￥" // 人民币符号

    const val ACTIVITY_JD_CASHIER_COMPLETE = "CashierUserContentCompleteActivity"
    // com.alipay.android.msp.ui.views.MspContainerActivity
    const val ACTIVITY_ALIPAY_MSP_CONTAINER = "MspContainerActivity"
    // 该页面金额动态显示，如需获取，需要监听TYPE_WINDOW_CONTENT_CHANGED
    const val ACTIVITY_ALIPAY_NRESPAGE =
            "com.alipay.android.phone.businesscommon.ucdp.nfc.activity.NResPageActivity"
    const val ACTIVITY_WECHAT_UIPAGEFRAGMENT = "com.tencent.mm.framework.app.UIPageFragmentActivity"
}
