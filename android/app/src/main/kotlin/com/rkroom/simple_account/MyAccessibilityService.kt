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
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*
import timber.log.Timber

// contentDescription，对于复杂的页面可考虑使用
data class NodeData(val windowId: Int, val viewId: String?, val text: String)

/**
 * 缓存
 * @param isComplete 是否已完成提取
 * @param recordId 数据库 ID
 */
private data class PageCacheEntry(
        val hash: Int,
        val timestamp: Long,
        val isComplete: Boolean,
        val recordId: String
)

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
    private val pageTriggerCounts = ConcurrentHashMap<PageIdentifier, Int>()
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    @Volatile private var cachedAllowedPackageNames: Set<String> = emptySet()
    @Volatile private var cachedExtractionRules: Map<String, List<ExtractionRule>> = emptyMap()
    private val windowChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    private val contentChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    @Volatile private var transactionCooldownMs: Long = 120000L
    @Volatile private var windowChangeDebounceMs: Long = 500L
    @Volatile private var contentChangeDebounceMs: Long = 500L
    @Volatile private var isContentChangeEnabled: Boolean = false
    @Volatile private var maxContentTriggerTimes: Int = 2

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

        val pageIdentifier = PageIdentifier(packageName, className)
        this.currentPageId = pageIdentifier
        pageTriggerCounts.clear()
        pageTriggerCounts[pageIdentifier] = 0

        // 查找规则
        val matchingRule = getOrFindRule(pageIdentifier) ?: return

        Timber.v(
                "匹配到无障碍事件: type=${AccessibilityEvent.eventTypeToString(event.eventType)}, pkg=${event.packageName}, class=${event.className}"
        )

        // 检查是否在冷却时间内 (针对空节点触发)
        if (matchingRule.triggerOnEmptyNodes) {
            val lastEntry = lastHashByPage.get(pageIdentifier)
            if (lastEntry != null) {
                val timeDiff = System.currentTimeMillis() - lastEntry.timestamp
                if (timeDiff < this.transactionCooldownMs) return
            }
        }

        contentChangeDebounceJobs[pageIdentifier]?.cancel()
        windowChangeDebounceJobs[pageIdentifier]?.cancel()

        val newJob =
                serviceScope.launch {
                    delay(windowChangeDebounceMs)

                    // 如果 this.currentPageId 变成了其他页面，当前任务作废
                    if (this@MyAccessibilityService.currentPageId != pageIdentifier) {
                        return@launch
                    }

                    // 提取
                    executeExtraction(pageIdentifier, matchingRule, isContentChange = false)
                    incrementTriggerCount(pageIdentifier)
                }

        windowChangeDebounceJobs[pageIdentifier] = newJob

        newJob.invokeOnCompletion { windowChangeDebounceJobs.remove(pageIdentifier, newJob) }
    }

    // 极端情况可考虑添加熔断
    private fun handleContentChange(event: AccessibilityEvent) {
        val currentId = currentPageId ?: return
        val packageName = event.packageName?.toString() ?: return

        if (packageName != currentId.packageName) return

        val matchingRule = getOrFindRule(currentId) ?: return

        if (!matchingRule.allowContentChangeTrigger) return

        val lastEntry = lastHashByPage.get(currentId)
        if (lastEntry != null && lastEntry.isComplete) {
            return
        }

        val currentCount = pageTriggerCounts[currentId] ?: 0
        if (currentCount >= maxContentTriggerTimes) {
            return
        }

        if (lastEntry != null) {
            val timeDiff = System.currentTimeMillis() - lastEntry.timestamp
            // 如果冷却期未过 且 数据已完整 -> 拦截
            if (timeDiff < transactionCooldownMs && lastEntry.isComplete) {
                return
            }
        }

        if (windowChangeDebounceJobs.containsKey(currentId)) return

        Timber.v(
                "匹配到无障碍事件: type=${AccessibilityEvent.eventTypeToString(event.eventType)}, pkg=${event.packageName}, class=${event.className}"
        )

        if (windowChangeDebounceJobs.containsKey(currentId)) {
            Timber.v("页面 ${currentId.className} 正在处理窗口事件，跳过内容检测。")
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
                            // 超出次数则不再执行
                            if ((pageTriggerCounts[currentId] ?: 0) >= maxContentTriggerTimes)
                                    return@launch

                            // 再次检查冷却时间 (防止防抖期间 WindowChange 刚好完成提取)
                            val freshLastEntry = lastHashByPage.get(currentId)
                            if (freshLastEntry != null &&
                                            (System.currentTimeMillis() - freshLastEntry.timestamp <
                                                    transactionCooldownMs) &&
                                            freshLastEntry.isComplete
                            ) {
                                return@launch
                            }

                            // 执行提取
                            executeExtraction(currentId, matchingRule, isContentChange = true)
                            incrementTriggerCount(currentId)
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
            matchingRule: ExtractionRule,
            isContentChange: Boolean
    ) {
        val usePlaceholder = matchingRule.triggerOnEmptyNodes && !isContentChange
        if (usePlaceholder) {
            processCollectedNodes(pageIdentifier, emptyList(), matchingRule, isContentChange)
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
                    processCollectedNodes(
                            pageIdentifier,
                            ArrayList(collectedNodes),
                            matchingRule,
                            isContentChange
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "提取过程发生异常")
            } finally {
                try {
                    rootNode.recycle()
                } catch (e: IllegalStateException) {
                    // 忽略已经回收的异常，防止崩溃
                }
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

        // IPC (跨进程) 调用，较为耗费性能
        // val tempRect = android.graphics.Rect()

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

            // IPC (跨进程) 调用，较为耗费性能
            // currentNode.getBoundsInScreen(tempRect)
            // if (tempRect.width() <= 0 || tempRect.height() <= 0) {
            //    currentNode.recycle()
            //    continue
            // }

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
                try {
                    currentNode.recycle()
                } catch (e: IllegalStateException) {
                    // 防御性捕获
                }
            }
        }
    }

    private suspend fun processCollectedNodes(
            pageIdentifierForProcessing: PageIdentifier,
            nodesToProcess: List<NodeData>,
            matchedRule: ExtractionRule,
            isContentChange: Boolean
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
                        saveIfNew(
                                content,
                                payment,
                                pageIdentifierForProcessing,
                                matchedRule,
                                isContentChange
                        )
                    }
                } else {
                    Timber.d("未从 pageId=$pageIdentifierForProcessing 中提取到任何内容。")
                }
            }

    private suspend fun saveIfNew(
            content: String?,
            payment: String?,
            pageIdentifier: PageIdentifier,
            rule: ExtractionRule,
            isContentChange: Boolean
    ) {
        if (content == null && payment == null) return

        val combinedHash = "c:${content}|p:${payment}".hashCode()
        val currentTime = System.currentTimeMillis()
        val lastEntry = lastHashByPage.get(pageIdentifier)

        // 是否饱和 (有 Content 且 (无需Payment 或 有Payment))
        val isDataComplete = (content != null) && (!rule.hasPaymentInfo || payment != null)

        var shouldSave = false
        //  默认生成新 ID
        var targetRecordId: String = UUID.randomUUID().toString()

        if (lastEntry == null) {
            //  首次记录 (使用新 ID)
            shouldSave = true
        } else {
            val isCoolingDown = (currentTime - lastEntry.timestamp) < transactionCooldownMs

            if (!isCoolingDown) {
                // 新交易 (使用新 ID)
                shouldSave = true
            } else {
                // 冷却期内 -> 检查更新
                if (lastEntry.hash != combinedHash) {
                    shouldSave = true
                    // 复用旧 ID，执行更新
                    targetRecordId = lastEntry.recordId
                    Timber.d("数据更新，ID: $targetRecordId")
                }
            }
        }

        if (shouldSave) {
            // 更新缓存
            val newEntry =
                    PageCacheEntry(
                            hash = combinedHash,
                            // 更新保持原时间戳
                            timestamp =
                                    if (lastEntry != null && lastEntry.recordId == targetRecordId)
                                            lastEntry.timestamp
                                    else currentTime,
                            isComplete = isDataComplete,
                            recordId = targetRecordId
                    )
            lastHashByPage.put(pageIdentifier, newEntry)

            saveData(pageIdentifier, content, payment, targetRecordId)
        }
    }

    private suspend fun saveData(
            pageIdentifier: PageIdentifier,
            content: String?,
            payment: String?,
            recordId: String
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
                        id = recordId,
                        title = pageIdentifier.className,
                        content = content,
                        packageName = packageName,
                        postTime = System.currentTimeMillis(),
                        payment = payment,
                        appName = appName
                )
        BillingRepository.saveBill(applicationContext, data)
    }

    private fun incrementTriggerCount(id: PageIdentifier) {
        pageTriggerCounts[id] = (pageTriggerCounts[id] ?: 0) + 1
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
