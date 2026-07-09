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

/**
 * 缓存
 * @param windowId 窗口ID (系统分配的唯一ID)
 * @param isComplete 是否已完成提取
 * @param recordId 数据库 ID
 * @param timestamp 首次创建时的时间戳
 * @param lastEmptyTriggerTime 上次触发 EmptyNode 规则的时间戳 (0 表示未触发过)
 * @param lastContent 上次缓存的 content，用于字段合并
 * @param lastPayment 上次缓存的 payment，用于字段合并
 */
private data class PageCacheEntry(
        // 屏幕旋转、系统深色模式切换等 Configuration Change 会导致 Activity 重建，WindowID 会发生改变
        // 特殊情况会导致重复记录，暂不处理
        val windowId: Int,
        val isComplete: Boolean,
        val recordId: String,
        val timestamp: Long,
        val lastEmptyTriggerTime: Long = 0L,
        val lastContent: String? = null,
        val lastPayment: String? = null
)

// 对同一个 PageIdentifier 的全部规则做一次“路径画像”
// - rules: 实际匹配到的 ExtractionRule 列表（原来缓存的内容）
// - hasAnyLazyRule: 是否存在需要 LazyDFS 的规则（非 FastPath 且非 triggerOnEmptyNodes）
// - hasAnyNonExactViewId: 是否存在 ExtractByViewId(useExactMatch = false) 的规则
private data class PageRuleBundle(
        val rules: List<ExtractionRule>,
        val hasAnyLazyRule: Boolean,
        val hasAnyNonExactViewId: Boolean
)

class MyAccessibilityService : AccessibilityService() {

    private val TAG = "AccService"

    companion object {
        private const val PAGE_HASH_CACHE_SIZE = 100
        private const val RULE_CACHE_SIZE = 200
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
            AppLog.d { "无障碍服务是否启用: $isEnabled" }
            return isEnabled
        }
    }

    @Volatile private var currentPageId: PageIdentifier? = null // 当前页面ID (包名/类名)
    @Volatile private var currentWindowId: Int = -1

    // 如果在多线程情况下崩溃可以考虑synchronized封装
    private val lastCacheByPage = LruCache<PageIdentifier, PageCacheEntry>(PAGE_HASH_CACHE_SIZE)
    private val ruleCache = LruCache<PageIdentifier, PageRuleBundle>(RULE_CACHE_SIZE)

    // 为 LRUCache 加锁
    private val lruCacheLock = Any()

    private fun getLastCacheEntry(pageIdentifier: PageIdentifier): PageCacheEntry? =
            synchronized(lruCacheLock) { lastCacheByPage.get(pageIdentifier) }

    private fun putLastCacheEntry(pageIdentifier: PageIdentifier, entry: PageCacheEntry) =
            synchronized(lruCacheLock) { lastCacheByPage.put(pageIdentifier, entry) }

    private fun evictAllLastCacheEntries() =
            synchronized(lruCacheLock) { lastCacheByPage.evictAll() }

    private fun getRuleBundleFromCache(pageIdentifier: PageIdentifier): PageRuleBundle? =
            synchronized(lruCacheLock) { ruleCache.get(pageIdentifier) }

    private fun putRuleBundleToCache(pageIdentifier: PageIdentifier, bundle: PageRuleBundle) =
            synchronized(lruCacheLock) { ruleCache.put(pageIdentifier, bundle) }

    private fun evictAllRuleBundles() = synchronized(lruCacheLock) { ruleCache.evictAll() }

    private val pageTriggerCounts = ConcurrentHashMap<PageIdentifier, Int>()
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var configObserveJob: Job? = null
    private var recordToastObserveJob: Job? = null
    @Volatile private var cachedAllowedPackageNames: Set<String> = emptySet()
    @Volatile private var cachedExtractionRules: Map<String, List<ExtractionRule>> = emptyMap()
    private val windowChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    private val contentChangeDebounceJobs = ConcurrentHashMap<PageIdentifier, Job>()
    @Volatile private var windowChangeDebounceMs: Long = 500L
    @Volatile private var contentChangeDebounceMs: Long = 500L
    @Volatile private var isContentChangeEnabled: Boolean = false
    @Volatile private var isRecordToastEnabled: Boolean = true

    private fun cancelAndClearJobs(map: ConcurrentHashMap<PageIdentifier, Job>, reason: String) {
        map.values.forEach { job ->
            try {
                job.cancel(reason)
            } catch (_: Exception) {}
        }
        map.clear()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        AppLog.i { "无障碍服务已连接。" }
        observeServiceConfig()
        observeRecordToastConfig()
    }

    private fun observeServiceConfig() {
        configObserveJob?.cancel("Restart service config observer")

        configObserveJob =
                serviceScope.launch {
                    val configManager = ConfigDataStoreManager.getInstance(applicationContext)

                    // 监听 Flow
                    configManager.serviceConfigFlow.collect { config ->
                        AppLog.d { "配置发生变更，正在刷新 Service 缓存..." }

                        cachedAllowedPackageNames = config.allowedPackageNames
                        cachedExtractionRules = config.extractionRules
                        windowChangeDebounceMs = config.windowChangeDebounceMs
                        contentChangeDebounceMs = config.contentChangeDebounceMs
                        isContentChangeEnabled = config.isContentChangeEnabled

                        // 清空规则查找缓存，因为规则可能变了
                        evictAllRuleBundles()

                        // 清空页面缓存，避免“已完成”的旧状态影响新规则
                        evictAllLastCacheEntries()

                        // 配置变更时取消旧的防抖任务，避免旧规则延迟后继续写库
                        cancelAndClearJobs(windowChangeDebounceJobs, "Config changed")
                        cancelAndClearJobs(contentChangeDebounceJobs, "Config changed")
                        pageTriggerCounts.clear()

                        // 更新 ServiceInfo (必须在主线程执行)
                        withContext(Dispatchers.Main) { updateServiceInfo(config) }

                        AppLog.i { "配置刷新完成。监听包数量: ${config.allowedPackageNames.size}" }
                    }
                }
    }

    private fun observeRecordToastConfig() {
        recordToastObserveJob?.cancel("Restart record toast config observer")

        recordToastObserveJob =
                serviceScope.launch {
                    val configManager = ConfigDataStoreManager.getInstance(applicationContext)

                    configManager.recordToastFlow.collect { enabled ->
                        isRecordToastEnabled = enabled
                        AppLog.d { "账单记录成功 Toast 提示: $enabled" }
                    }
                }
    }

    private fun updateServiceInfo(config: ServiceConfig) {
        AppLog.d { "正在更新服务信息 (启用页面内容变更监测: ${config.isContentChangeEnabled})" }
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
                        arrayOf(DUMMY_PACKAGE_NAME)
                    } else {
                        config.allowedPackageNames.toTypedArray()
                    }
        }
        setServiceInfo(currentServiceInfo)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val packageName = event.packageName?.toString() ?: return
        val allowedPackages = cachedAllowedPackageNames
        if (allowedPackages.isEmpty() || packageName !in allowedPackages) {
            return
        }
        val eventType = event.eventType
        val eventWindowId = event.windowId

        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val previousWindowId = currentWindowId
            currentWindowId = eventWindowId

            val className = event.className?.toString() ?: AppConstants.UNKNOWN_CLASS
            val newPageId = PageIdentifier(packageName, className)

            val lastEntry = getLastCacheEntry(newPageId)
            if (lastEntry != null && lastEntry.windowId == eventWindowId && lastEntry.isComplete) {
                return
            }

            AppLog.d {
                "[$TAG] WindowStateChanged: $packageName / $className (WinID: $eventWindowId)"
            }

            //  在事件发生时捕获 targetWindowId
            val targetWindowId = eventWindowId
            handleWindowStateChanged(newPageId, targetWindowId, previousWindowId)
        } else if (eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            if (eventWindowId != currentWindowId) {
                return
            }

            val activePageId = currentPageId ?: return
            if (activePageId.packageName != packageName) return
            if (!isContentChangeEnabled) return

            // AppLog.v { "[$TAG] ContentChanged: WinID: $eventWindowId" }

            // 在事件发生时捕获 targetWindowId
            val targetWindowId = eventWindowId
            handleWindowContentChanged(event, activePageId, targetWindowId)
        }
    }

    // 只触发一次 ContentChange 且 source 不是目标 view”的极端情况会漏账单
    private fun quickCheckEventMatchesRules(
            event: AccessibilityEvent,
            rules: List<ExtractionRule>
    ): Boolean {
        if (rules.isEmpty()) return false

        val interestingKeywords = mutableSetOf<String>()
        val interestingViewIds = mutableSetOf<String>()

        rules.forEach { rule ->
            (rule.contentRules + rule.paymentRules).forEach { detail ->
                interestingKeywords.addAll(detail.keywords)
                when (val strategy = detail.strategy) {
                    is DirectViewId -> interestingViewIds.add(strategy.viewId)
                    is ExtractByViewId -> interestingViewIds.add(strategy.viewId)
                    else -> {}
                }
            }
        }

        if (interestingKeywords.isNotEmpty()) {
            val eventTextList = event.text
            for (text in eventTextList) {
                val s = text.toString()
                if (interestingKeywords.any { s.contains(it, ignoreCase = true) }) {
                    AppLog.v { "[$TAG] 快速预检: Event文本命中 -> $s" }
                    return true
                }
            }
        }

        val sourceNode = event.source ?: return false
        return sourceNode.use { node ->
            // 只做浅层检查，不遍历子节点
            if (interestingViewIds.isNotEmpty()) {
                val nodeId = node.viewIdResourceName
                if (nodeId != null &&
                                interestingViewIds.any { viewId ->
                                    if (viewId.contains(":id/")) nodeId == viewId
                                    else nodeId.endsWith(viewId)
                                }
                ) {
                    AppLog.v { "[$TAG] 快速预检: Event节点ID命中 -> $nodeId" }
                    return@use true
                }
            }
            if (interestingKeywords.isNotEmpty()) {
                val nodeText = node.text?.toString()
                if (nodeText != null &&
                                interestingKeywords.any { nodeText.contains(it, ignoreCase = true) }
                ) {
                    AppLog.v { "[$TAG] 快速预检: Event节点文本命中 -> $nodeText" }
                    return@use true
                }
                val nodeDesc = node.contentDescription?.toString()
                if (nodeDesc != null &&
                                interestingKeywords.any { nodeDesc.contains(it, ignoreCase = true) }
                ) {
                    AppLog.v { "[$TAG] 快速预检: Event描述命中 -> $nodeDesc" }
                    return@use true
                }
            }
            false
        }
    }

    private fun getRootInWindow(targetWindowId: Int): AccessibilityNodeInfo? {
        val windows = this.windows
        val targetWindow = windows.find { it.id == targetWindowId }
        return targetWindow?.root
    }

    /** 按 PageIdentifier 缓存/获取所有匹配该 Activity 的规则（按配置顺序） */
    private fun getOrFindRuleBundle(pageIdentifier: PageIdentifier): PageRuleBundle {
        getRuleBundleFromCache(pageIdentifier)?.let {
            return it
        }

        val allRulesForPackage = cachedExtractionRules[pageIdentifier.packageName].orEmpty()

        val matched =
                allRulesForPackage.filter { rule ->
                    rule.activityName.isNotBlank() &&
                            pageIdentifier.className.endsWith(rule.activityName, ignoreCase = true)
                }

        // 规则层面的路径画像（对“当前页面下匹配到的所有规则”做一次统计）
        val hasAnyNonExactViewId =
                matched.any { rule ->
                    (rule.contentRules + rule.paymentRules).any {
                        (it.strategy as? ExtractByViewId)?.useExactMatch == false
                    }
                }
        val disablePrefilterPage = hasAnyNonExactViewId

        val hasAnyLazyRule =
                matched.any { rule ->
                    if (rule.triggerOnEmptyNodes) return@any false
                    val effectivePrefilter = rule.preFilterByKeywords && !disablePrefilterPage
                    effectivePrefilter || !Extractor.isFastPathRule(rule)
                }

        val bundle =
                PageRuleBundle(
                        rules = matched,
                        hasAnyLazyRule = hasAnyLazyRule,
                        hasAnyNonExactViewId = hasAnyNonExactViewId
                )

        // 就算 rules 为空也缓存，避免后续重复计算
        putRuleBundleToCache(pageIdentifier, bundle)
        return bundle
    }

    private suspend fun performExtraction(
            pageId: PageIdentifier,
            rootNode: AccessibilityNodeInfo,
            rule: ExtractionRule,
            windowId: Int,
            isContentChange: Boolean,
            isFinalAttempt: Boolean,
            nodeProvider: Extractor.LazyNodeProvider? = null,
            disablePrefilter: Boolean = false,
    ): Boolean {
        if (rootNode.packageName?.toString() != pageId.packageName) return false
        AppLog.d { "[$TAG] 执行提取逻辑 -> WindowID: $windowId" }

        val result =
                Extractor.extract(
                        pageIdentifier = pageId,
                        root = rootNode,
                        matchedRule = rule,
                        isContentChange = isContentChange,
                        isFinalAttempt = isFinalAttempt,
                        sharedProvider = nodeProvider,
                        disablePrefilter = disablePrefilter,
                )
        if (result != null) {
            withContext(Dispatchers.IO) {
                saveIfNew(
                        content = result.first,
                        payment = result.second,
                        pageIdentifier = pageId,
                        rule = rule,
                        currentWindowId = windowId,
                        updateEmptyTriggerTime = null
                )
            }
            return true
        }
        return false
    }

    // 如遇线程问题导致的崩溃，可考虑在防抖结束之后切换到主线程生成节点快照，然后在后台线程处理
    private fun handleWindowStateChanged(
            newPageId: PageIdentifier,
            targetWindowId: Int,
            previousWindowId: Int
    ) {
        val oldPageId = currentPageId
        val isPageChanged = oldPageId != null && oldPageId != newPageId
        val isWindowChanged = previousWindowId != targetWindowId

        currentPageId = newPageId

        if (isPageChanged) {
            windowChangeDebounceJobs[oldPageId]?.cancel("Page changed")
            windowChangeDebounceJobs.remove(oldPageId)

            contentChangeDebounceJobs[oldPageId]?.cancel("Page changed")
            contentChangeDebounceJobs.remove(oldPageId)

            pageTriggerCounts.remove(oldPageId)
        } else if (oldPageId == newPageId && isWindowChanged) {
            // 同一个 Activity 进入新窗口时，取消旧窗口遗留的 ContentChange 防抖任务
            contentChangeDebounceJobs[newPageId]?.cancel("Window changed")
            contentChangeDebounceJobs.remove(newPageId)
        }

        // 只有页面变化、窗口变化或首次进入时才重置触发次数，避免重复 WindowState 重置计数
        if (oldPageId == null || isPageChanged || isWindowChanged) {
            pageTriggerCounts[newPageId] = 0
        }

        contentChangeDebounceJobs[newPageId]?.let { job ->
            if (job.isActive) {
                AppLog.d { "[$TAG] 互斥避让: 检测到 ContentChange 正在运行，WindowState 放弃执行。" }
                return
            }
        }

        val bundle = getOrFindRuleBundle(newPageId)
        val rules = bundle.rules
        if (rules.isEmpty()) return

        windowChangeDebounceJobs[newPageId]?.cancel()
        val job =
                serviceScope.launch {
                    try {
                        delay(windowChangeDebounceMs)
                        if (currentPageId != newPageId) return@launch

                        // 以页面为单位的重试次数：取该页面所有规则中的最大 dynamicRetryTimes
                        val maxDynamicRetry = rules.maxOfOrNull { it.dynamicRetryTimes } ?: 0
                        val maxAttempts = 1 + maxDynamicRetry
                        var attempt = 0
                        var extractionSuccess = false

                        val hasLazyRule = bundle.hasAnyLazyRule

                        while (attempt < maxAttempts && !extractionSuccess) {
                            val isFinalAttempt = attempt >= maxAttempts - 1
                            if (attempt > 0) {
                                val retryInterval =
                                        rules.maxOfOrNull { it.dynamicRetryIntervalMs } ?: 1000L
                                delay(retryInterval)
                                if (currentPageId != newPageId || !isActive) break
                            }

                            val root =
                                    withContext(Dispatchers.Main) {
                                        try {
                                            if (currentPageId != newPageId) null
                                            else getRootInWindow(targetWindowId)
                                        } catch (e: Exception) {
                                            null
                                        }
                                    }

                            if (root == null) {
                                AppLog.v {
                                    "[$TAG] WindowState: 第 ${attempt + 1} 次尝试 root 为空，继续重试。"
                                }
                                attempt++
                                continue
                            }

                            val currentWindowId = root.windowId
                            val nodeProvider =
                                    if (hasLazyRule) Extractor.LazyNodeProvider(root) else null

                            try {
                                val lastEntry = getLastCacheEntry(newPageId)
                                if (lastEntry != null &&
                                                lastEntry.windowId == currentWindowId &&
                                                lastEntry.isComplete
                                ) {
                                    AppLog.d { "[$TAG] 防抖后检查: 页面已完成，跳过。" }
                                    return@launch
                                }

                                // 依次尝试每一条规则
                                for (rule in rules) {
                                    if (rule.triggerOnEmptyNodes) {
                                        val now = System.currentTimeMillis()
                                        val cooldown = rule.emptyNodeTriggerCooldownMs
                                        val lastTriggerTime = lastEntry?.lastEmptyTriggerTime ?: 0L

                                        if (cooldown > 0 && lastTriggerTime > 0L) {
                                            val timeDiff = now - lastTriggerTime
                                            if (timeDiff < cooldown) {
                                                AppLog.d {
                                                    "EmptyNode冷却拦截: ${newPageId.className} " +
                                                            "(剩余 ${cooldown - timeDiff}ms, WindowID: $currentWindowId)"
                                                }
                                                // 该规则跳过，尝试下一条
                                                continue
                                            }
                                        }

                                        AppLog.d {
                                            "EmptyNode触发: rule=${rule.ruleName}, WinID: $currentWindowId"
                                        }

                                        val staticContent =
                                                buildStaticContentForEmptyNodeTrigger(rule)
                                        val contentToSave = staticContent ?: ""
                                        val paymentToSave = ""

                                        withContext(Dispatchers.IO) {
                                            saveIfNew(
                                                    content = contentToSave,
                                                    payment = paymentToSave,
                                                    pageIdentifier = newPageId,
                                                    rule = rule,
                                                    currentWindowId = currentWindowId,
                                                    updateEmptyTriggerTime = now
                                            )
                                        }
                                        extractionSuccess = true
                                        break
                                    } else {
                                        val success =
                                                performExtraction(
                                                        pageId = newPageId,
                                                        rootNode = root,
                                                        rule = rule,
                                                        windowId = currentWindowId,
                                                        isContentChange = false,
                                                        isFinalAttempt = isFinalAttempt,
                                                        nodeProvider = nodeProvider,
                                                        disablePrefilter =
                                                                bundle.hasAnyNonExactViewId,
                                                )
                                        if (success) {
                                            AppLog.d {
                                                "[$TAG] WindowState: 规则 ${rule.ruleName} 提取成功 (第 ${attempt + 1} 次尝试)"
                                            }
                                            extractionSuccess = true
                                            break
                                        } else {
                                            AppLog.v {
                                                "[$TAG] WindowState: 规则 ${rule.ruleName} 提取失败 (第 ${attempt + 1} 次尝试)"
                                            }
                                        }
                                    }
                                }
                            } finally {
                                try {
                                    nodeProvider?.recycle()
                                } catch (e: Exception) {}
                                try {
                                    root.recycle()
                                } catch (e: Exception) {}
                            }
                            attempt++
                        }
                    } finally {
                        val selfJob = this.coroutineContext[Job]
                        if (selfJob != null) {
                            windowChangeDebounceJobs.remove(newPageId, selfJob)
                        }
                    }
                }

        windowChangeDebounceJobs[newPageId] = job
    }

    private fun buildStaticContentForEmptyNodeTrigger(rule: ExtractionRule): String? {
        val concatRule = rule.contentRules.firstOrNull { it.strategy is Concatenate }
        val concat = concatRule?.strategy as? Concatenate ?: return null

        if (concat.parts.isEmpty()) return null

        val literalTexts = concat.parts.mapNotNull { (it as? Literal)?.text }
        // 只在所有 part 都是 Literal 时才认为是“静态 Concatenate”
        return if (literalTexts.size == concat.parts.size) {
            literalTexts.joinToString(separator = "")
        } else {
            null
        }
    }

    private fun handleWindowContentChanged(
            event: AccessibilityEvent,
            pageId: PageIdentifier,
            targetWindowId: Int
    ) {
        val lastEntry = getLastCacheEntry(pageId)
        if (lastEntry != null && lastEntry.windowId == targetWindowId && lastEntry.isComplete) {
            // AppLog.v { "[$TAG] 窗口($targetWindowId)已提取完成，忽略 ContentChange" }
            return
        }

        val bundle = getOrFindRuleBundle(pageId)
        val allRules = bundle.rules
        if (allRules.isEmpty()) return

        // ContentChange 只针对允许 allowContentChangeTrigger 且不使用 triggerOnEmptyNodes 的规则
        val contentChangeRules =
                allRules.filter { it.allowContentChangeTrigger && !it.triggerOnEmptyNodes }
        if (contentChangeRules.isEmpty()) return

        if (!quickCheckEventMatchesRules(event, contentChangeRules)) {
            return
        }

        // 以页面为单位控制触发次数：取该页面所有 ContentChange 规则中的最大值
        val maxTriggerTimesOfAll = contentChangeRules.maxOf { it.maxContentTriggerTimes }
        val currentCountSnapshot = pageTriggerCounts[pageId] ?: 0

        if (currentCountSnapshot >= maxTriggerTimesOfAll) {
            AppLog.v { "[$TAG] 已达到最大触发次数限制 ($maxTriggerTimesOfAll)，忽略变更" }
            return
        }

        // 抢占
        windowChangeDebounceJobs[pageId]?.let { wsJob ->
            if (wsJob.isActive) {
                AppLog.d { "[$TAG] 抢占模式: 有效 ContentChange 触发，取消旧的 WindowState 任务。" }
                wsJob.cancel("Preempted by valid ContentChange")
            }
        }

        contentChangeDebounceJobs[pageId]?.cancel()
        val job =
                serviceScope.launch {
                    try {
                        delay(contentChangeDebounceMs)
                        if (currentPageId != pageId || currentWindowId != targetWindowId)
                                return@launch

                        val root =
                                withContext(Dispatchers.Main) {
                                    try {
                                        getRootInWindow(targetWindowId)
                                    } catch (e: Exception) {
                                        null
                                    }
                                }

                        if (root == null || root.windowId != targetWindowId) {
                            root?.let {
                                try {
                                    it.recycle()
                                } catch (e: Exception) {}
                            }
                            return@launch
                        }

                        val currentWindowId = root.windowId

                        val hasLazyRule = contentChangeRules.any { !Extractor.isFastPathRule(it) }
                        val nodeProvider =
                                if (hasLazyRule) Extractor.LazyNodeProvider(root) else null

                        try {
                            val freshLast = getLastCacheEntry(pageId)
                            if (freshLast != null &&
                                            freshLast.windowId == currentWindowId &&
                                            freshLast.isComplete
                            ) {
                                return@launch
                            }

                            AppLog.d { "[$TAG] ContentChange 防抖结束，触发提取. WinID: $currentWindowId" }

                            val newCount = (pageTriggerCounts[pageId] ?: 0) + 1
                            pageTriggerCounts[pageId] = newCount

                            for (rule in contentChangeRules) {
                                val isFinal = newCount >= rule.maxContentTriggerTimes

                                val success =
                                        performExtraction(
                                                pageId = pageId,
                                                rootNode = root,
                                                rule = rule,
                                                windowId = currentWindowId,
                                                isContentChange = true,
                                                isFinalAttempt = isFinal,
                                                nodeProvider = nodeProvider,
                                        )
                                if (success) {
                                    AppLog.d {
                                        "[$TAG] ContentChange: 规则 ${rule.ruleName} 提取成功 (第 $newCount 次, Final=$isFinal)"
                                    }
                                    break
                                } else {
                                    AppLog.v {
                                        "[$TAG] ContentChange: 规则 ${rule.ruleName} 提取失败 (第 $newCount 次, Final=$isFinal)"
                                    }
                                }
                            }
                        } finally {
                            try {
                                nodeProvider?.recycle()
                            } catch (e: Exception) {}
                            try {
                                root.recycle()
                            } catch (e: Exception) {}
                        }
                    } finally {
                        val selfJob = this.coroutineContext[Job]
                        if (selfJob != null) {
                            contentChangeDebounceJobs.remove(pageId, selfJob)
                        }
                    }
                }
        contentChangeDebounceJobs[pageId] = job
    }

    private suspend fun saveIfNew(
            content: String?,
            payment: String?,
            pageIdentifier: PageIdentifier,
            rule: ExtractionRule,
            currentWindowId: Int,
            updateEmptyTriggerTime: Long?
    ) {
        val lastEntry = getLastCacheEntry(pageIdentifier)

        val usingEmptyNodeTrigger = rule.triggerOnEmptyNodes

        val previousContent = lastEntry?.lastContent
        val previousPayment = lastEntry?.lastPayment

        val mergedContent =
                when {
                    content == null -> previousContent
                    content.isEmpty() && !previousContent.isNullOrEmpty() -> previousContent
                    else -> content
                }

        val mergedPayment = payment ?: previousPayment

        // 当前数据是否“完整”
        val isCurrentDataComplete =
                if (usingEmptyNodeTrigger) {
                    // triggerOnEmptyNodes：进入页面即视为一次“完整记录”
                    true
                } else {
                    // 常规提取：以合并后的字段判断完整性
                    !mergedContent.isNullOrEmpty() &&
                            (!rule.hasPaymentInfo || mergedPayment != null)
                }

        var shouldSave = false
        var targetRecordId = UUID.randomUUID().toString()
        var logReason = ""

        val currentTime = System.currentTimeMillis()
        var targetTimestamp = currentTime

        if (lastEntry == null) {
            // 首次出现该页面
            shouldSave = true
            targetTimestamp = currentTime
            logReason = "New(无缓存)"
        } else {
            if (lastEntry.windowId != currentWindowId) {
                // 同一 PageIdentifier 但 WindowID 变了，视为新页面
                shouldSave = true
                targetTimestamp = currentTime
                logReason = "New(WinID变动: ${lastEntry.windowId}->${currentWindowId})"
            } else {
                if (lastEntry.isComplete) {
                    AppLog.v { "Window($currentWindowId) 已标记为完整，跳过。" }
                    return
                } else {
                    // 未完成，复用旧 recordId 做更新，同时保留第一次缓存时间
                    shouldSave = true
                    targetRecordId = lastEntry.recordId
                    targetTimestamp = lastEntry.timestamp
                    logReason =
                            if (isCurrentDataComplete) {
                                "Update(数据补全)"
                            } else {
                                "Update(数据刷新)"
                            }
                }
            }
        }

        if (shouldSave) {
            val newTriggerTime = updateEmptyTriggerTime ?: lastEntry?.lastEmptyTriggerTime ?: 0L

            val newEntry =
                    PageCacheEntry(
                            windowId = currentWindowId,
                            isComplete = isCurrentDataComplete,
                            recordId = targetRecordId,
                            timestamp = targetTimestamp,
                            lastEmptyTriggerTime = newTriggerTime,
                            lastContent = mergedContent,
                            lastPayment = mergedPayment
                    )
            putLastCacheEntry(pageIdentifier, newEntry)

            if (mergedContent != null || mergedPayment != null || rule.triggerOnEmptyNodes) {
                AppLog.i {
                    "写入数据库 [$logReason]: ID=$targetRecordId, Win=$currentWindowId, 完整=$isCurrentDataComplete"
                }
                saveData(
                        pageIdentifier,
                        mergedContent,
                        mergedPayment,
                        targetRecordId,
                        targetTimestamp
                )
            }
        }
    }

    private suspend fun saveData(
            pageIdentifier: PageIdentifier,
            content: String?,
            payment: String?,
            recordId: String,
            timestamp: Long
    ) {
        val packageName = pageIdentifier.packageName
        val activityTitle = pageIdentifier.className

        if (packageName == AppConstants.UNKNOWN_PACKAGE ||
                        activityTitle == AppConstants.UNKNOWN_CLASS
        ) {
            return
        }

        AppLog.d { "saveData 方法被调用，准备构建 billData..." }

        val sourceAppName = AppUtils.getAppName(applicationContext, packageName)
        val selfAppName = getString(R.string.app_name)

        val data =
                BillData(
                        id = recordId,
                        title = pageIdentifier.className,
                        content = content,
                        packageName = packageName,
                        postTime = timestamp,
                        payment = payment,
                        appName = sourceAppName
                )

        BillDataStoreManager.getInstance(applicationContext).saveBillAsync(data)

        withContext(Dispatchers.Main) {
            if (!isRecordToastEnabled) return@withContext

            val detailParts = buildList {
                if (!content.isNullOrBlank()) add(content)
                if (!payment.isNullOrBlank()) add("支付方式: $payment")
            }

            val detailText = detailParts.joinToString("，")

            val toastMessage =
                    if (BuildConfig.DEBUG) {
                        if (detailText.isBlank()) {
                            "$selfAppName：已记录。$packageName"
                        } else {
                            "$selfAppName：已记录，$detailText。$packageName"
                        }
                    } else {
                        if (detailText.isBlank()) {
                            "$selfAppName：已记录。"
                        } else {
                            "$selfAppName：已记录，$detailText"
                        }
                    }

            Toast.makeText(this@MyAccessibilityService, toastMessage, Toast.LENGTH_LONG).show()
        }
    }

    override fun onInterrupt() {
        AppLog.w { "无障碍服务被中断。" }
        cancelAndClearJobs(windowChangeDebounceJobs, "Service interrupted")
        cancelAndClearJobs(contentChangeDebounceJobs, "Service interrupted")
        pageTriggerCounts.clear()
    }

    override fun onDestroy() {
        super.onDestroy()
        AppLog.w { "无障碍服务被销毁。" }
        cancelAndClearJobs(windowChangeDebounceJobs, "Service destroyed")
        cancelAndClearJobs(contentChangeDebounceJobs, "Service destroyed")
        pageTriggerCounts.clear()
        configObserveJob?.cancel("Service destroyed")
        recordToastObserveJob?.cancel("Service destroyed")
        serviceScope.cancel()
    }
}
