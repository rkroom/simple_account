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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MyNotificationListenerService : NotificationListenerService() {

    private val billManager by lazy { BillDataStoreManager.getInstance(this) }
    private val configManager by lazy { ConfigDataStoreManager.getInstance(this) }
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    @Volatile private var cachedAllowPackageName: List<String>? = null
    @Volatile private var cachedAllowKeywords: List<String>? = null
    private val staticRegExp = Regex("(\\d+\\.\\d{2})")

    fun refreshCachedConfig() {
        serviceScope.launch { loadAndCacheConfig() }
    }

    private suspend fun loadAndCacheConfig() {
        cachedAllowPackageName =
                configManager.getNlAllowPackageConfig().filter { it.isAllowed }.map {
                    it.packageName
                }
        cachedAllowKeywords = configManager.getAllowKeywords()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        serviceScope.launch {
            val notification = sbn.notification
            if (notification != null) {
                val title = notification.extras.getString(Notification.EXTRA_TITLE)
                val content = notification.extras.getString(Notification.EXTRA_TEXT)
                val packageName = sbn.packageName
                val postTime = sbn.postTime
                if (cachedAllowPackageName == null || cachedAllowKeywords == null) {
                    loadAndCacheConfig()
                }
                handleNotification(title, content, packageName, postTime)
            }
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
        BillingRepository.saveBill(applicationContext, notificationData)
    }

    private suspend fun handleNotification(
            title: String?,
            content: String?,
            packageName: String?,
            postTime: Long?
    ) {
        val localPackageCache = cachedAllowPackageName ?: return
        val localKeywordsCache = cachedAllowKeywords ?: return

        if (!localPackageCache.contains(packageName)) {
            return
        }

        if (!localKeywordsCache.any { title?.contains(it, ignoreCase = true) == true }) {
            return
        }

        if (staticRegExp.find(content ?: "") == null) {
            return
        }

        saveNotificationData(title, content, packageName, postTime)
    }

    override fun onCreate() {
        super.onCreate()
        serviceScope.launch { loadAndCacheConfig() }
    }

    override fun onDestroy() {
        super.onDestroy()
        Companion.clearActiveInstance(this)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Companion.setActiveInstance(this)
        serviceScope.launch { loadAndCacheConfig() }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Companion.clearActiveInstance(this)
        val componentName = ComponentName(this, MyNotificationListenerService::class.java)
        try {
            requestRebind(componentName)
        } catch (e: Exception) {
            // 在某些系统版本上可能会有异常，进行保护
        }
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
                } else {
                    Handler(Looper.getMainLooper()).post { serviceInstance.refreshCachedConfig() }
                }
            }
        }

        fun isNotificationListenerEnabled(context: Context): Boolean {
            val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
            return enabledPackages.contains(context.packageName)
        }
    }
}
