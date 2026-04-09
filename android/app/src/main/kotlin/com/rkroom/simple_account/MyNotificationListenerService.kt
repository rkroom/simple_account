package com.rkroom.simple_account

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MyNotificationListenerService : NotificationListenerService() {

    private val configManager by lazy { ConfigDataStoreManager.getInstance(this) }
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    @Volatile private var cachedAllowPackageName: Set<String> = emptySet()
    @Volatile private var cachedAllowKeywords: List<String> = emptyList()
    private val staticRegExp = Regex("(\\d+\\.\\d{2})")

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        // 未来可考虑sbn.notification.flags
        if (sbn.isOngoing) return
        if (sbn.packageName !in cachedAllowPackageName) {
            return
        }
        serviceScope.launch {
            val notification = sbn.notification ?: return@launch
            val title = notification.extras.getString(Notification.EXTRA_TITLE)
            val content = notification.extras.getString(Notification.EXTRA_TEXT)

            handleNotification(title, content, sbn.packageName, sbn.postTime)
        }
    }

    private suspend fun saveNotificationData(
            title: String?,
            content: String?,
            packageName: String?,
            postTime: Long?
    ) {
        val appName = AppUtils.getAppName(applicationContext, packageName)
        val notificationData =
                BillData(
                        title = title,
                        content = content,
                        packageName = packageName,
                        postTime = postTime,
                        payment = null,
                        appName = appName
                )
        BillDataStoreManager.getInstance(applicationContext).saveBillAsync(notificationData)
        AppLog.i { "账单已保存-通知: ${notificationData.appName}" }
    }

    private suspend fun handleNotification(
            title: String?,
            content: String?,
            packageName: String?,
            postTime: Long?
    ) {
        if (title.isNullOrEmpty() || content.isNullOrEmpty()) return

        val currentKeywords = cachedAllowKeywords

        val hasKeyword =
                currentKeywords.any { keyword -> title.contains(keyword, ignoreCase = true) }
        if (!hasKeyword) return

        if (!staticRegExp.containsMatchIn(content)) return

        saveNotificationData(title, content, packageName, postTime)
    }

    override fun onCreate() {
        AppLog.i { "通知监听服务已创建" }
        super.onCreate()
    }

    override fun onDestroy() {
        AppLog.i { "通知监听服务已销毁" }
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onListenerConnected() {
        AppLog.i { "通知监听服务已连接" }
        super.onListenerConnected()
        observeNotificationConfig()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        AppLog.i { "通知监听服务已断开" }
        val componentName = ComponentName(this, MyNotificationListenerService::class.java)
        try {
            requestRebind(componentName)
        } catch (e: Exception) {
            // 在某些系统版本上可能会有异常，进行保护
        }
    }

    private fun observeNotificationConfig() {
        serviceScope.launch {
            configManager.notificationConfigFlow.collect { config ->
                AppLog.d {
                    "通知配置更新: 包名数量=${config.allowedPackages.size}, 关键字数量=${config.keywords.size}"
                }
                cachedAllowPackageName = config.allowedPackages
                cachedAllowKeywords = config.keywords
            }
        }
    }

    companion object {

        const val PERMISSION_REQUEST_CODE = 1

        fun isNotificationListenerEnabled(context: Context): Boolean {
            val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
            return enabledPackages.contains(context.packageName)
        }
    }
}
