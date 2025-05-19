package com.rkroom.simple_account

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import java.lang.ref.WeakReference
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class MyNotificationListenerService : NotificationListenerService() {

    private val sharedPreferencesManager by lazy { SharedPreferencesManager.getInstance(this) }
    private val configPreferencesManager by lazy { ConfigPreferencesManager.getInstance(this) }

    private lateinit var cachedAllowPackageName: List<String>
    private lateinit var cachedAllowKeywords: List<String>
    private val staticRegExp = Regex("(\\d+\\.\\d{2})")

    fun refreshCachedConfig() {
        loadAndCacheConfig()
    }

    private fun loadAndCacheConfig() {
        cachedAllowPackageName =
                configPreferencesManager.getNlAllowPackageConfig().filter { it.isAllowed }.map {
                    it.packageName
                }
        cachedAllowKeywords = configPreferencesManager.getAllowKeywords()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)

        val notification = sbn.notification
        if (notification != null) {
            val title = notification.extras.getString(Notification.EXTRA_TITLE)
            val content = notification.extras.getString(Notification.EXTRA_TEXT)
            val packageName = sbn.packageName
            val postTime = sbn.postTime

            if (!::cachedAllowPackageName.isInitialized || !::cachedAllowKeywords.isInitialized) {
                loadAndCacheConfig()
                if (!::cachedAllowPackageName.isInitialized || !::cachedAllowKeywords.isInitialized
                ) {
                    return
                }
            }

            handleNotification(title, content, packageName, postTime)
        }
    }

    private fun saveNotificationData(
            title: String?,
            content: String?,
            packageName: String?,
            postTime: Long?
    ) {
        val notificationData =
                billData(
                        title = title,
                        content = content,
                        packageName = packageName,
                        postTime = postTime,
                        payment = null
                )

        val jsonString = Json.encodeToString(notificationData)

        sharedPreferencesManager.addBill(jsonString)

        // 发送账单，以便在打开bill_listener页面时也能及时添加新的账单
        // 在需要的情况下
        // 可以调用MisAppRunning检查应用的运行情况
        // 同时设置一个标志位（isSendNotification）,在进入bill_listener时修改其状态，退出时还原状态
        // 在两者同时满足的情况下才发送账单
        /*
        channel?.invokeMethod("onNotificationPosted", mapOf(
            "title" to title,
            "content" to content,
            "packageName" to packageName,
            "postTime" to postTime,
        ))
        */
    }

    private fun handleNotification(
            title: String?,
            content: String?,
            packageName: String?,
            postTime: Long?
    ) {

        if (!cachedAllowPackageName.contains(packageName)) {
            return
        }

        if (!cachedAllowKeywords.any { title?.contains(it, ignoreCase = true) == true }) {
            return
        }

        if (staticRegExp.find(content ?: "") == null) {
            return
        }

        saveNotificationData(title, content, packageName, postTime)
    }

    override fun onCreate() {
        super.onCreate()
        loadAndCacheConfig()
    }

    override fun onDestroy() {
        super.onDestroy()
        Companion.clearActiveInstance(this)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Companion.setActiveInstance(this)
        loadAndCacheConfig()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Companion.clearActiveInstance(this)
        val componentName = ComponentName(this, MyNotificationListenerService::class.java)
        requestRebind(componentName)
    }

    companion object {

        const val PERMISSION_REQUEST_CODE = 1

        private var activeInstanceRef: WeakReference<MyNotificationListenerService>? = null

        internal fun setActiveInstance(service: MyNotificationListenerService) {
            activeInstanceRef = WeakReference(service)
        }

        internal fun clearActiveInstance(service: MyNotificationListenerService) {
            if (activeInstanceRef?.get() == service) {
                activeInstanceRef?.clear()
                activeInstanceRef = null
            }
        }

        fun notifyConfigurationChanged(context: Context) {
            if (!isNotificationListenerEnabled(context)) {
                return
            }
            val serviceInstance = activeInstanceRef?.get()
            if (serviceInstance != null) {
                if (Looper.myLooper() == Looper.getMainLooper()) {
                    serviceInstance.refreshCachedConfig()
                    // Log.d("NotificationListener", "已在主线程直接刷新缓存。")
                } else {
                    Handler(Looper.getMainLooper()).post {
                        serviceInstance.refreshCachedConfig()
                        // Log.d("NotificationListener", "已将缓存刷新任务提交到主线程。")
                    }
                }
            } else {
                // Log.d("NotificationListener", "未找到活动的 MyNotificationListenerService
                // 实例以通知配置更改...")
            }
        }

        // var isSendNotification: Boolean = false

        fun isNotificationListenerEnabled(context: Context): Boolean {
            val packageName = context.packageName
            val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
            return enabledPackages.contains(packageName)
        }
    }
}
