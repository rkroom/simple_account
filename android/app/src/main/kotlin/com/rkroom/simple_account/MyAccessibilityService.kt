package com.rkroom.simple_account

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import androidx.collection.LruCache
import io.flutter.BuildConfig
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*
import timber.log.Timber

data class NodeData(val windowId: Int, val viewId: String?, val text: String)

private data class PageCacheEntry(val hash: Int, val timestamp: Long)

private data class CachedRuleResult(val rule: ExtractionRule?)

class MyAccessibilityService : AccessibilityService() {

    companion object {
        private const val PAGE_HASH_CACHE_SIZE = 100
        private const val RULE_CACHE_SIZE = 200
        private const val TAG = "AccessibilityTracker"
        private const val DUMMY_PACKAGE_NAME = "com.example.nonexistent.package"

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
    }

    @Volatile private var currentPageId: PageIdentifier? = null // 当前页面ID (包名/类名)
    private val lastHashByPage = LruCache<PageIdentifier, PageCacheEntry>(PAGE_HASH_CACHE_SIZE)
    private val ruleCache = LruCache<PageIdentifier, CachedRuleResult>(RULE_CACHE_SIZE)
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    @Volatile private var cachedAllowedPackageNames: Set<String> = emptySet()
    @Volatile private var cachedExtractionRules: Map<String, List<ExtractionRule>> = emptyMap()
    private val windowChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    private val contentChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    @Volatile private var transactionCooldownMs: Long = 120000L
    @Volatile private var windowChangeDebounceMs: Long = 500L
    @Volatile private var contentChangeDebounceMs: Long = 500L
    @Volatile private var isContentChangeEnabled: Boolean = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        Timber.i("无障碍服务已连接。")
        observeServiceConfig()
    }

    private fun observeServiceConfig() {
        serviceScope.launch {
            val configManager = ConfigDataStoreManager.getInstance(applicationContext)

            // 监听 Flow
            configManager.serviceConfigFlow.collect { config ->
                Timber.d("配置发生变更，正在刷新 Service 缓存...")

                cachedAllowedPackageNames = config.allowedPackageNames
                cachedExtractionRules = config.extractionRules
                transactionCooldownMs = config.transactionCooldownMs
                windowChangeDebounceMs = config.windowChangeDebounceMs
                contentChangeDebounceMs = config.contentChangeDebounceMs
                isContentChangeEnabled = config.isContentChangeEnabled

                // 清空规则查找缓存，因为规则可能变了
                ruleCache.evictAll()

                // 更新 ServiceInfo (必须在主线程执行)
                withContext(Dispatchers.Main) { updateServiceInfo(config) }

                Timber.i("配置刷新完成。监听包数量: ${config.allowedPackageNames.size}")
            }
        }
    }

    private fun updateServiceInfo(config: ServiceConfig) {
        val currentServiceInfo = serviceInfo ?: AccessibilityServiceInfo()
        currentServiceInfo.apply {
            eventTypes =
                    if (config.isContentChangeEnabled) {
                        AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                    } else {
                        AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                    }
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100
            flags =
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                            AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS

            packageNames =
                    if (config.allowedPackageNames.isEmpty()) {
                        arrayOf("com.example.nonexistent.package")
                    } else {
                        config.allowedPackageNames.toTypedArray()
                    }
        }
        setServiceInfo(currentServiceInfo)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        // 降低日志级别，避免 TYPE_WINDOW_CONTENT_CHANGED 刷屏
        // Timber.v(
        //        "收到无障碍事件: type=${AccessibilityEvent.eventTypeToString(event.eventType)},
        // pkg=${event.packageName}, class=${event.className}"
        // )
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> handleWindowChange(event)
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                if (isContentChangeEnabled) {
                    handleContentChange(event)
                }
            }
        }
    }

    private fun getOrFindRule(pageIdentifier: PageIdentifier): ExtractionRule? {

        val cachedResult = ruleCache.get(pageIdentifier)
        if (cachedResult != null) {
            return cachedResult.rule
        }

        val rulesForPackage = cachedExtractionRules[pageIdentifier.packageName]

        val matchedRule =
                rulesForPackage?.find { rule ->
                    pageIdentifier.className.endsWith(rule.activityName, ignoreCase = true)
                }

        ruleCache.put(pageIdentifier, CachedRuleResult(matchedRule))

        return matchedRule
    }

    // 如遇线程问题导致的崩溃，可考虑在防抖结束之后切换到主线程生成节点快照，然后在后台线程处理
    private fun handleWindowChange(event: AccessibilityEvent) {
        val packageName = event.packageName?.toString() ?: AppConstants.UNKNOWN_PACKAGE
        val className = event.className?.toString() ?: AppConstants.UNKNOWN_CLASS

        if (className == AppConstants.UNKNOWN_CLASS) return

        val pageIdentifierForDebounce = PageIdentifier(packageName, className)

        this.currentPageId = pageIdentifierForDebounce

        // 查找规则
        val matchingRule = getOrFindRule(pageIdentifierForDebounce) ?: return

        Timber.v(
                "匹配到无障碍事件: type=${AccessibilityEvent.eventTypeToString(event.eventType)}, pkg=${event.packageName}, class=${event.className}"
        )

        // 检查是否在冷却时间内 (针对空节点触发)
        if (matchingRule.triggerOnEmptyNodes) {
            val lastEntry = lastHashByPage.get(pageIdentifierForDebounce)
            if (lastEntry != null) {
                val timeDiff = System.currentTimeMillis() - lastEntry.timestamp
                if (timeDiff < this.transactionCooldownMs) return
            }
        }

        contentChangeDebounceJobs[pageIdentifierForDebounce]?.cancel()
        windowChangeDebounceJobs[pageIdentifierForDebounce]?.cancel()

        val newJob =
                serviceScope.launch {
                    delay(windowChangeDebounceMs)

                    // 如果 this.currentPageId 变成了其他页面，当前任务作废
                    if (this@MyAccessibilityService.currentPageId != pageIdentifierForDebounce) {
                        return@launch
                    }

                    // 提取
                    executeExtraction(pageIdentifierForDebounce, matchingRule)
                }

        windowChangeDebounceJobs[pageIdentifierForDebounce] = newJob

        newJob.invokeOnCompletion {
            windowChangeDebounceJobs.remove(pageIdentifierForDebounce, newJob)
        }
    }

    // 极端情况可考虑添加熔断
    private fun handleContentChange(event: AccessibilityEvent) {
        val currentId = currentPageId ?: return
        val packageName = event.packageName?.toString() ?: return

        if (packageName != currentId.packageName) return

        val matchingRule = getOrFindRule(currentId) ?: return

        if (!matchingRule.allowContentChangeTrigger) {
            return
        }

        Timber.v(
                "匹配到无障碍事件: type=${AccessibilityEvent.eventTypeToString(event.eventType)}, pkg=${event.packageName}, class=${event.className}"
        )

        // 空节点触发在handleWindowChange中已经处理。
        if (matchingRule.triggerOnEmptyNodes) return

        val lastEntry = lastHashByPage.get(currentId)
        if (lastEntry != null) {
            val timeDiff = System.currentTimeMillis() - lastEntry.timestamp
            if (timeDiff < this.transactionCooldownMs) {
                Timber.v("优化：页面 ${currentId.className} 已在冷却期内，跳过内容检测。")
                return
            }
        }

        if (windowChangeDebounceJobs.containsKey(currentId)) {
            Timber.v("优化：页面 ${currentId.className} 正在处理窗口事件，跳过内容检测。")
            return
        }

        contentChangeDebounceJobs[currentId]?.cancel()
        contentChangeDebounceJobs[currentId] =
                serviceScope
                        .launch {
                            delay(contentChangeDebounceMs)

                            // 环境检查
                            if (currentPageId != currentId) {
                                return@launch
                            }

                            // 再次检查冷却时间 (防止防抖期间 WindowChange 刚好完成提取)
                            val freshLastEntry = lastHashByPage.get(currentId)
                            if (freshLastEntry != null &&
                                            (System.currentTimeMillis() - freshLastEntry.timestamp <
                                                    transactionCooldownMs)
                            ) {
                                return@launch
                            }

                            // 执行提取
                            executeExtraction(currentId, matchingRule)
                        }
                        .also { job ->
                            job.invokeOnCompletion {
                                if (contentChangeDebounceJobs[currentId] == job) {
                                    contentChangeDebounceJobs.remove(currentId)
                                }
                            }
                        }
    }

    private suspend fun executeExtraction(
            pageIdentifier: PageIdentifier,
            matchingRule: ExtractionRule
    ) {
        if (matchingRule.triggerOnEmptyNodes) {
            processCollectedNodes(pageIdentifier, emptyList(), matchingRule)
        } else {
            val rootNode = rootInActiveWindow ?: return
            try {
                if (rootNode.packageName?.toString() != pageIdentifier.packageName) {
                    Timber.w(
                            "界面已切换 (预期: ${pageIdentifier.packageName}, 实际: ${rootNode.packageName})，放弃提取"
                    )
                    return
                }

                // 前置关键字过滤
                // 如果关键字多，则取消预过滤，直接进行一次全量遍历匹配
                if (matchingRule.preFilterByKeywords) {
                    val allKeywords =
                            (matchingRule.contentRules.flatMap { it.keywords } +
                                            matchingRule.paymentRules.flatMap { it.keywords })
                                    .distinct()

                    if (allKeywords.isNotEmpty()) {
                        val keywordFound =
                                allKeywords.any { keyword ->
                                    rootNode.findAccessibilityNodeInfosByText(keyword)
                                            ?.isNotEmpty() == true
                                }
                        if (!keywordFound) return
                    }
                }

                // 收集节点
                val collectedNodes = mutableListOf<NodeData>()
                traverseAndCollect(rootNode, collectedNodes)

                if (collectedNodes.isNotEmpty()) {
                    processCollectedNodes(pageIdentifier, ArrayList(collectedNodes), matchingRule)
                }
            } finally {
                rootNode.recycle()
            }
        }
    }

    private fun traverseAndCollect(
            node: AccessibilityNodeInfo?,
            collectedNodes: MutableList<NodeData>
    ) {
        node ?: return

        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.addLast(node)

        val visitedNodes = mutableSetOf<AccessibilityNodeInfo>()

        val tempRect = android.graphics.Rect()

        // 不处理不可见节点
        while (stack.isNotEmpty()) {
            val currentNode = stack.removeLast()

            if (!visitedNodes.add(currentNode)) {
                // recycle由系统管理，可以不手动回收。
                currentNode.recycle()
                continue
            }

            if (!currentNode.isVisibleToUser) {
                currentNode.recycle()
                continue
            }

            currentNode.getBoundsInScreen(tempRect)
            if (tempRect.width() <= 0 || tempRect.height() <= 0) {
                currentNode.recycle()
                continue
            }

            currentNode.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { text ->
                collectedNodes.add(
                        NodeData(currentNode.windowId, currentNode.viewIdResourceName, text)
                )
            }

            for (i in (currentNode.childCount - 1) downTo 0) {
                currentNode.getChild(i)?.let { childNode -> stack.addLast(childNode) }
            }

            // AccessibilityNodeInfo 对象由系统管理，可以不需要手动回收它们
            if (currentNode !== node) {
                currentNode.recycle()
            }
        }
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
        contentChangeDebounceJobs.clear()
        serviceScope.cancel()
    }

    override fun onDestroy() {
        super.onDestroy()
        Timber.w("无障碍服务被销毁。")
        windowChangeDebounceJobs.values.forEach { it.cancel("Service destroyed") }
        windowChangeDebounceJobs.clear()
        contentChangeDebounceJobs.clear()
        serviceScope.cancel()
    }
}
