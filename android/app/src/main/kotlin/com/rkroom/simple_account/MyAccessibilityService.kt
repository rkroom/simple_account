package com.rkroom.simple_account

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import androidx.collection.LruCache
import io.flutter.BuildConfig
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*
import timber.log.Timber

data class NodeData(val windowId: Int, val viewId: String?, val text: String)

private data class PageCacheEntry(val hash: Int, val timestamp: Long)

class MyAccessibilityService : AccessibilityService() {

    companion object {
        private const val PAGE_HASH_CACHE_SIZE = 100
        private const val TAG = "AccessibilityTracker"
        // private const val CONTENT_CHANGE_DEBOUNCE_MS = 1000L
        private const val DUMMY_PACKAGE_NAME = "com.example.nonexistent.package"
        @Volatile var currentPageId: PageIdentifier? = null // 当前页面ID (包名/类名)
        // 指向当前服务实例的弱引用 (WeakReference)
        private var activeServiceInstance: WeakReference<MyAccessibilityService>? = null

        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            val accessibilityManager =
                    context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
                            ?: return false
            val expectedServiceId =
                    ComponentName(context, MyAccessibilityService::class.java)
                            .flattenToShortString()

            val enabledServices =
                    accessibilityManager.getEnabledAccessibilityServiceList(
                            AccessibilityServiceInfo.FEEDBACK_ALL_MASK
                    )
                            ?: return false

            val isEnabled =
                    enabledServices.any { serviceInfo -> serviceInfo.id == expectedServiceId }
            Timber.d("无障碍服务是否启用: $isEnabled")
            return isEnabled
        }

        fun triggerRefreshAllowedPackagesCache(context: Context) {
            Timber.d("触发允许的包名缓存刷新...")
            if (!isAccessibilityServiceEnabled(context)) {
                return
            }
            val serviceInstance = activeServiceInstance?.get()
            if (serviceInstance != null) {
                if (Looper.myLooper() == Looper.getMainLooper()) {
                    serviceInstance.refreshAllowedPackagesCacheFromCompanion()
                } else {
                    Handler(Looper.getMainLooper()).post {
                        serviceInstance.refreshAllowedPackagesCacheFromCompanion()
                    }
                }
            } else {
                Timber.w("无法刷新缓存：MyAccessibilityService 实例不可用或已被垃圾回收。")
            }
        }
    }

    private val lastHashByPage = LruCache<PageIdentifier, PageCacheEntry>(PAGE_HASH_CACHE_SIZE)
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var cachedAllowedPackageNames: Array<String>? = null
    @Volatile private var cachedExtractionRules: Map<String, List<ExtractionRule>> = emptyMap()
    private val windowChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    @Volatile private var transactionCooldownMs: Long = 120000L
    @Volatile private var windowChangeDebounceMs: Long = 500L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Timber.i("无障碍服务已连接。")
        activeServiceInstance = WeakReference(this)
        refreshAllowedPackagesCacheInternal()
    }

    private fun refreshAllowedPackagesCacheInternal() {
        serviceScope.launch {
            Timber.d("开始刷新内部缓存...")
            val configManager = ConfigDataStoreManager.getInstance(this@MyAccessibilityService)
            val allowedPackageConfigs = configManager.getAbAllowPackageConfig()
            val localAllowedPackageNames =
                    allowedPackageConfigs
                            .filter { it.isAllowed }
                            .map { it.packageName }
                            .toTypedArray()

            val localExtractionRules = configManager.getExtractionRules()
            val cooldown = configManager.getTransactionCooldownMs()
            val debounceMs = configManager.getWindowChangeDebounceMs()

            Timber.d("获取到 ${localAllowedPackageNames.size} 个允许的包名。")
            Timber.d("获取到 ${localExtractionRules.size} 条提取规则。")
            Timber.d("获取到交易冷却时间: $cooldown ms。")
            Timber.d("获取到窗口变化防抖时间: $debounceMs ms。") // 新增日志

            // 更新 ServiceInfo 必须在主线程
            withContext(Dispatchers.Main) {
                this@MyAccessibilityService.cachedAllowedPackageNames = localAllowedPackageNames
                this@MyAccessibilityService.cachedExtractionRules =
                        localExtractionRules.groupBy { it.packageName }
                this@MyAccessibilityService.transactionCooldownMs = cooldown
                this@MyAccessibilityService.windowChangeDebounceMs = debounceMs // 更新缓存的防抖时间

                val currentServiceInfo =
                        this@MyAccessibilityService.serviceInfo ?: AccessibilityServiceInfo()
                currentServiceInfo.apply {
                    eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED // or
                    // 	   AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                    feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
                    notificationTimeout = 100
                    flags =
                            AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                    packageNames =
                            if (this@MyAccessibilityService.cachedAllowedPackageNames
                                            .isNullOrEmpty()
                            ) {
                                arrayOf(DUMMY_PACKAGE_NAME) // 设置为一个不存在的包名
                            } else {
                                this@MyAccessibilityService.cachedAllowedPackageNames
                            }
                }
                setServiceInfo(currentServiceInfo)
                Timber.i("ServiceInfo 已更新，监听的包: ${cachedAllowedPackageNames?.joinToString()}.")
            }
        }
    }

    private fun refreshAllowedPackagesCacheFromCompanion() {
        refreshAllowedPackagesCacheInternal()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        Timber.v(
                "收到无障碍事件: type=${AccessibilityEvent.eventTypeToString(event.eventType)}, pkg=${event.packageName}, class=${event.className}"
        )
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> handleWindowChange(event)
        // AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> handleContentChange(event)
        }
    }

    // 如遇线程问题导致的崩溃，可考虑在防抖结束之后切换到主线程生成节点快照，然后在后台线程处理
    private fun handleWindowChange(event: AccessibilityEvent) {
        val packageName = event.packageName?.toString() ?: AppConstants.UNKNOWN_PACKAGE
        val className = event.className?.toString() ?: AppConstants.UNKNOWN_CLASS

        if (className == AppConstants.UNKNOWN_CLASS) {
            Timber.v("忽略 className 无效的窗口事件: pkg=$packageName")
            return
        }

        val pageIdentifierForDebounce = PageIdentifier(packageName, className)

        val matchingRule =
                cachedExtractionRules[packageName]?.find { rule ->
                    className.endsWith(rule.activityName)
                }

        if (matchingRule == null) {
            Timber.v("忽略无匹配规则的窗口事件: pageId=$pageIdentifierForDebounce")
            return
        }

        if (matchingRule.triggerOnEmptyNodes) {
            val lastEntry = lastHashByPage.get(pageIdentifierForDebounce)
            if (lastEntry != null) {
                val timeDiff = System.currentTimeMillis() - lastEntry.timestamp
                if (timeDiff < this.transactionCooldownMs) {
                    Timber.d(
                            "提前跳过: 规则 '${matchingRule.ruleName}' 仍在冷却期内 " +
                                    "($timeDiff ms < ${this.transactionCooldownMs} ms)。" +
                                    "不启动防抖任务。"
                    )
                    return
                }
            }
        }

        currentPageId = pageIdentifierForDebounce
        Timber.d("处理窗口变化: pageId=$pageIdentifierForDebounce. 重置防抖任务。")

        windowChangeDebounceJobs[pageIdentifierForDebounce]?.cancel()

        windowChangeDebounceJobs[pageIdentifierForDebounce] =
                serviceScope
                        .launch {
                            delay(windowChangeDebounceMs)
                            Timber.d("防抖延迟结束，开始处理 pageId=$pageIdentifierForDebounce")

                            val currentGlobalPageIdAfterDelay = currentPageId
                            if (activeServiceInstance?.get() == null ||
                                            currentGlobalPageIdAfterDelay !=
                                                    pageIdentifierForDebounce
                            ) {
                                Timber.d(
                                        "跳过处理：服务实例为空或页面已改变 (当前: $currentGlobalPageIdAfterDelay, 预期: $pageIdentifierForDebounce)"
                                )
                                return@launch
                            }

                            if (matchingRule.triggerOnEmptyNodes) {
                                Timber.i(
                                        "规则 (ruleName='${matchingRule.ruleName}') 允许在空节点上触发，跳过节点收集，直接处理。"
                                )
                                processCollectedNodes(
                                        pageIdentifierForDebounce,
                                        emptyList(),
                                        matchingRule
                                )
                            } else {
                                val rootNode = rootInActiveWindow
                                if (rootNode == null) {
                                    Timber.w(
                                            "rootInActiveWindow 为空，无法为 pageId=$pageIdentifierForDebounce 收集节点。"
                                    )
                                    return@launch
                                }

                                if (matchingRule.preFilterByKeywords) {
                                    val allKeywords =
                                            (matchingRule.contentRules.flatMap { it.keywords } +
                                                            matchingRule.paymentRules.flatMap {
                                                                it.keywords
                                                            })
                                                    .distinct()

                                    if (allKeywords.isNotEmpty()) {
                                        val keywordFound =
                                                allKeywords.any { keyword ->
                                                    rootNode.findAccessibilityNodeInfosByText(
                                                                    keyword
                                                            )
                                                            ?.isNotEmpty() == true
                                                }

                                        if (!keywordFound) {
                                            Timber.d(
                                                    "前置过滤：在页面上未找到任何目标关键字，跳过对 pageId=$pageIdentifierForDebounce 的节点遍历。"
                                            )
                                            return@launch
                                        }
                                        Timber.d("前置过滤：成功找到关键字，继续执行节点遍历。")
                                    }
                                }

                                val collectedNodesForThisEvent = mutableListOf<NodeData>()
                                traverseAndCollect(rootNode, collectedNodesForThisEvent)
                                Timber.d(
                                        "节点遍历完成，为 pageId=$pageIdentifierForDebounce 收集到 ${collectedNodesForThisEvent.size} 个节点。"
                                )
                                if (collectedNodesForThisEvent.isNotEmpty()) {
                                    Timber.d("节点不为空，开始处理。")
                                    processCollectedNodes(
                                            pageIdentifierForDebounce,
                                            ArrayList(collectedNodesForThisEvent),
                                            matchingRule
                                    )
                                } else {
                                    Timber.d("节点为空，且规则不允许无条件触发，跳过处理。")
                                }
                            }
                        }
                        .also { job ->
                            job.invokeOnCompletion {
                                if (windowChangeDebounceJobs[pageIdentifierForDebounce] == job) {
                                    windowChangeDebounceJobs.remove(pageIdentifierForDebounce)
                                }
                            }
                        }
    }
    /*
        private fun handleContentChange(event: AccessibilityEvent) {
            val pageIdForContentChange = currentPageId // 捕获事件发生时的 pageId
            if (!isValidPageId(pageIdForContentChange)) {
                // 可选: 记录接收到无效的 PageId 用于内容更改
                return
            }
            // 取消此特定 pageId 已有的任何防抖任务
            contentChangeDebounceJobs[pageIdForContentChange]?.cancel()

            // 启动一个新的防抖任务
            contentChangeDebounceJobs[pageIdForContentChange] =
                serviceScope
                    .launch {
                        delay(CONTENT_CHANGE_DEBOUNCE_MS)

                        // 延迟之后，检查服务是否仍处于活动状态以及页面上下文是否仍然相同。
                        // 这可以防止在防抖期间用户导航离开或服务停止时进行处理。
                        val currentActivePageId =
                            MyAccessibilityService.currentPageId // 获取最新的 currentPageId
                        if (activeServiceInstance?.get() == null ||
                            currentActivePageId != pageIdForContentChange
                        ) {
                            // 可选: 记录在防抖期间上下文已更改或服务变为非活动状态
                            if (currentActivePageId != pageIdForContentChange) {
                                // Log.d(TAG, "页面ID在防抖期间从 $pageIdForContentChange 变为
                                // $currentActivePageId。跳过。")
                            }
                            return@launch
                        }

                        val collectedNodesForThisEvent = mutableListOf<NodeData>()
                        // 对于延迟后处理的内容更改，通常更可靠的做法是使用 rootInActiveWindow，
                        // 因为事件对象或其 source 可能已被回收或变得陈旧。
                        val rootNode = rootInActiveWindow

                        if (rootNode != null) {
                            traverseAndCollect(rootNode, collectedNodesForThisEvent)
                            // 注意: rootInActiveWindow 不需要由服务显式回收。
                            // 如果您在这里使用 event.source，则需要注意其生命周期。
                        } else {
                            // 可选: 记录在防抖后 pageIdForContentChange 的 rootNode 为 null
                            return@launch
                        }

                        if (collectedNodesForThisEvent.isNotEmpty()) {
                            // 处理收集到的节点。此调用已通过 processCollectedNodes 在后台线程上执行。
                            processCollectedNodes(
                                pageIdForContentChange,
                                ArrayList(collectedNodesForThisEvent)
                            )
                        } else {
                            // 可选: 记录在防抖后没有为 pageIdForContentChange 收集到节点
                        }
                    }
                    .also { job ->
                        // 当任务完成时（正常完成或被取消），将其从映射中移除。
                        job.invokeOnCompletion {
                            // 确保我们只移除相同的任务实例，以防止竞争条件。
                            if (contentChangeDebounceJobs[pageIdForContentChange] == job) {
                                contentChangeDebounceJobs.remove(pageIdForContentChange)
                            }
                        }
                    }
        }
    */

    private fun traverseAndCollect(
            node: AccessibilityNodeInfo?,
            collectedNodes: MutableList<NodeData>
    ) {
        node ?: return

        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.addLast(node)
        val visitedNodes = mutableSetOf<AccessibilityNodeInfo>()

        while (stack.isNotEmpty()) {
            val currentNode = stack.removeLast()

            if (!visitedNodes.add(currentNode)) {
                continue
            }

            // 收集节点信息
            currentNode.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { text ->
                collectedNodes.add(
                        NodeData(currentNode.windowId, currentNode.viewIdResourceName, text)
                )
            }

            for (i in (currentNode.childCount - 1) downTo 0) {
                currentNode.getChild(i)?.let { stack.addLast(it) }
            }
        }
        // AccessibilityNodeInfo 对象由系统管理，不需要手动回收它们
    }

    private suspend fun processCollectedNodes(
            pageIdentifierForProcessing: PageIdentifier,
            nodesToProcess: List<NodeData>,
            matchedRule: ExtractionRule
    ) =
            withContext(Dispatchers.IO) {
                Timber.d(
                        "在IO线程中处理节点: pageId=$pageIdentifierForProcessing, 节点数=${nodesToProcess.size}"
                )

                // 调用 Extractor.extract 方法，并传入 PageIdentifier 对象和对应的规则
                val extractionResult =
                        Extractor.extract(pageIdentifierForProcessing, nodesToProcess, matchedRule)

                if (extractionResult != null) {
                    val (content, payment) = extractionResult
                    Timber.i(
                            "提取成功: pageId=$pageIdentifierForProcessing, content='${content?.take(50)}...', payment='$payment'"
                    )
                    if (content != null || payment != null) {
                        saveIfNew(content, payment, pageIdentifierForProcessing)
                    }
                } else {
                    Timber.d("未从 pageId=$pageIdentifierForProcessing 中提取到任何内容。")
                }
            }

    private suspend fun saveIfNew(
            content: String?,
            payment: String?,
            pageIdentifier: PageIdentifier
    ) {
        // 如果没有提取到任何有效内容，则直接返回
        if (content == null && payment == null) {
            return
        }

        // 将提取出的 content 和 payment 组合成一个字符串，用于生成哈希值
        val combinedDataForHash = "content:${content ?: "null"}|payment:${payment ?: "null"}"
        val currentHash = combinedDataForHash.hashCode()
        // 获取当前时间戳
        val currentTime = System.currentTimeMillis()
        Timber.d("saveIfNew检查: pageId=$pageIdentifier, hash=$currentHash")
        // 从缓存中获取上次针对该页面的记录项
        Timber.d("即将从 LruCache 获取 pageId: %s 的条目...", pageIdentifier)
        val lastEntry = lastHashByPage.get(pageIdentifier)
        Timber.d("LruCache.get 完成。lastEntry 是否为 null: %s", lastEntry == null)

        // 判断是否应该保存的逻辑
        val shouldSave =
                if (lastEntry == null) {
                    Timber.d("决策: 保存。原因: 首次记录该页面。")
                    true
                } else if (lastEntry.hash != currentHash) {
                    Timber.d("决策: 保存。原因: 内容哈希已改变 (旧=${lastEntry.hash}, 新=$currentHash)。")
                    true
                } else {
                    val timeDiff = currentTime - lastEntry.timestamp
                    val decision = timeDiff > this.transactionCooldownMs
                    Timber.d(
                            "决策: ${if (decision) "保存" else "跳过"}。原因: 内容哈希相同，时间差 ($timeDiff ms) vs 冷却时间 (${this.transactionCooldownMs} ms)。"
                    )
                    decision
                }

        // 如果判断结果为应该保存
        if (shouldSave) {
            Timber.i("正在为 pageId=$pageIdentifier 保存新条目...")
            // 创建一个新的缓存条目，包含新的哈希和当前时间戳
            val newEntry = PageCacheEntry(hash = currentHash, timestamp = currentTime)
            // 将新条目放入缓存，覆盖旧的记录
            lastHashByPage.put(pageIdentifier, newEntry)
            // 调用方法，将数据真正地保存到数据库
            saveData(pageIdentifier, content, payment)
        } else {
            Timber.w("决策为 '跳过'，saveData 方法不会被调用。")
        }
    }

    private suspend fun saveData(
            pageIdentifier: PageIdentifier,
            content: String?,
            payment: String?
    ) {
        val packageName = pageIdentifier.packageName
        val activityTitle = pageIdentifier.className

        if (packageName == AppConstants.UNKNOWN_PACKAGE ||
                        activityTitle == AppConstants.UNKNOWN_CLASS
        ) {
            return
        }

        if (BuildConfig.DEBUG) {
            // Toast 必须在主线程上显示
            withContext(Dispatchers.Main) {
                val toastMessage = "记录已保存，来自：$packageName"
                Toast.makeText(this@MyAccessibilityService, toastMessage, Toast.LENGTH_SHORT).show()
            }
        }

        Timber.d("saveData 方法被调用，准备构建 billData...")
        val appName = AppUtils.getAppName(applicationContext, packageName)

        val data =
                BillData(
                        title = activityTitle,
                        content = content,
                        packageName = packageName,
                        postTime = System.currentTimeMillis(),
                        payment = payment,
                        appName = appName
                )
        BillingRepository.saveBill(applicationContext, data)
    }

    override fun onInterrupt() {
        Timber.w("无障碍服务被中断。")
        windowChangeDebounceJobs.values.forEach { it.cancel("Service interrupted") }
        windowChangeDebounceJobs.clear()
        serviceScope.cancel()
        if (activeServiceInstance?.get() == this) {
            activeServiceInstance?.clear()
            activeServiceInstance = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Timber.w("无障碍服务被销毁。")
        windowChangeDebounceJobs.values.forEach { it.cancel("Service destroyed") }
        windowChangeDebounceJobs.clear()
        serviceScope.cancel()
        if (activeServiceInstance?.get() == this) {
            activeServiceInstance?.clear()
            activeServiceInstance = null
        }
    }
}
