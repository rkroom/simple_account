package com.rkroom.simple_account

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Context
import android.content.ComponentName
import androidx.core.app.NotificationManagerCompat
import android.app.Notification
import io.flutter.plugin.common.MethodChannel

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class MyNotificationListenerService : NotificationListenerService() {

    private val sharedPreferencesManager by lazy {
        SharedPreferencesManager.getInstance(this)
    }

    private val allowPackageName = listOf(
        "com.eg.android.AlipayGphone",
        "com.tencent.mm",
    ) 
    private val allowKeywords = listOf("交易", "支付",)
    private val regExp = Regex("(\\d+\\.\\d{2})")


    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)

        val notification = sbn.notification
        if (notification != null) {
            val title = notification.extras.getString(Notification.EXTRA_TITLE)
            val content = notification.extras.getString(Notification.EXTRA_TEXT)
            val packageName = sbn.packageName
            val postTime = sbn.postTime

            handleNotification(title, content, packageName, postTime)
        }
    }

    private fun saveNotificationData(title: String?, content: String?, packageName: String?, postTime: Long?) {
        val notificationData = NotificationData(
            title = title,
            content = content,
            packageName = packageName,
            postTime = postTime
        )
        
        // 使用 Kotlinx.serialization 序列化为 JSON 字符串
        val jsonString = Json.encodeToString(notificationData)
    
        sharedPreferencesManager.addBill(jsonString)

        //发送账单，以便在打开bill_listener页面时也能及时添加新的账单
        //在需要的情况下
        //可以调用MisAppRunning检查应用的运行情况
        //同时设置一个标志位（isSendNotification）,在进入bill_listener时修改其状态，退出时还原状态
        //在两者同时满足的情况下才发送账单
        /* 
        channel?.invokeMethod("onNotificationPosted", mapOf(
            "title" to title,
            "content" to content,
            "packageName" to packageName,
            "postTime" to postTime,
        ))
        */
    }

    private fun handleNotification(title: String?, content: String?, packageName: String?,postTime: Long?) {

        // 检查 packageName 是否在允许的列表中
        if (!allowPackageName.contains(packageName)) {
            return
        }

        // 检查 title 中是否包含允许的关键字
        if (!allowKeywords.any { title?.contains(it, ignoreCase = true) == true }) {
            return
        }
        
        if (regExp.find(content ?: "") == null) {
            return
        }

        saveNotificationData(title, content, packageName, postTime)
        
    }

    //检测APP是否运行中
    /*
    private fun isAppRunning(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val runningProcesses = activityManager.runningAppProcesses
        runningProcesses?.forEach { processInfo ->
            if (processInfo.processName == packageName) {
                return true
            }
        }
        return false
    }
    */

    /* 
    override fun onCreate() {
        super.onCreate()
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
    }
    */
    
    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        //当监听断开时，触发rebind
        val componentName = ComponentName(this, MyNotificationListenerService::class.java)
        requestRebind(componentName)
    }

    companion object {
        var channel: MethodChannel? = null

        const val PERMISSION_REQUEST_CODE = 1

        //var isSendNotification: Boolean = false

        fun isNotificationListenerEnabled(context: Context): Boolean {
            val packageName = context.packageName
            val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
            return enabledPackages.contains(packageName)
        }

        fun flutterPrint(message:Any?){
            channel?.invokeMethod("flutterPrint",message.toString())
        }
    }
}

@Serializable
data class NotificationData(
    val title: String?,
    val content: String?,
    val packageName: String?,
    val postTime: Long?
)