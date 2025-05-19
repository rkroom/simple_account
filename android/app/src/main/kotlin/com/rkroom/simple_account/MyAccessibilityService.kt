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
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class NodeData(val windowId: Int, val viewId: String?, val text: String)

class MyAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "AccessibilityTracker"
        // private const val CONTENT_CHANGE_DEBOUNCE_MS = 1000L
        private const val WINDOW_CHANGE_DEBOUNCE_MS = 500L // 毫秒
        @Volatile var currentPageId: String = "" // 当前页面ID (包名/类名)

        // 指向当前服务实例的弱引用 (WeakReference)
        private var activeServiceInstance: WeakReference<MyAccessibilityService>? = null

        private fun buildPageId(packageName: CharSequence?, className: CharSequence?): String {
            val pkg = packageName?.toString() ?: AppConstants.UNKNOWN_PACKAGE
            val cls = className?.toString() ?: AppConstants.UNKNOWN_CLASS
            return "$pkg/$cls"
        }

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

            return enabledServices.any { serviceInfo -> serviceInfo.id == expectedServiceId }
        }

        fun triggerRefreshAllowedPackagesCache(context: Context) {
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
                // "无法刷新缓存：MyAccessibilityService 实例不可用或已被垃圾回收。"
            }
        }
    }

    private val lastHashByPage = ConcurrentHashMap<String, Int>()
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var cachedAllowedPackageNames: Array<String>? = null

    private val windowChangeDebounceJobs = ConcurrentHashMap<String, Job>()
    // private val contentChangeDebounceJobs = ConcurrentHashMap<String, Job>()

    override fun onServiceConnected() {
        super.onServiceConnected()
        activeServiceInstance = WeakReference(this)
        refreshAllowedPackagesCacheInternal()
    }

    private fun refreshAllowedPackagesCacheInternal() {
        val configManager = ConfigPreferencesManager.getInstance(this)
        val allowedPackageConfigs = configManager.getAbAllowPackageConfig()
        val localAllowedPackageNames =
                allowedPackageConfigs.filter { it.isAllowed }.map { it.packageName }.toTypedArray()

        this.cachedAllowedPackageNames = localAllowedPackageNames

        val currentServiceInfo = this.serviceInfo ?: AccessibilityServiceInfo()
        currentServiceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED // or
            //      AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100 // 毫秒
            flags =
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                            AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS

            packageNames =
                    if (this@MyAccessibilityService.cachedAllowedPackageNames.isNullOrEmpty()) {
                        emptyArray<String>() // 设置为空数组，尝试不监听任何应用
                    } else {
                        this@MyAccessibilityService.cachedAllowedPackageNames
                    }
        }
        setServiceInfo(currentServiceInfo)
    }

    private fun refreshAllowedPackagesCacheFromCompanion() {
        refreshAllowedPackagesCacheInternal()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> handleWindowChange(event)
        // AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> handleContentChange(event)
        }
    }

    private fun handleWindowChange(event: AccessibilityEvent) {

        val pageIdForDebounce = buildPageId(event.packageName, event.className)
        currentPageId = pageIdForDebounce

        windowChangeDebounceJobs[pageIdForDebounce]?.cancel()

        // 启动一个新的协程作为防抖任务
        windowChangeDebounceJobs[pageIdForDebounce] =
                serviceScope
                        .launch {
                            delay(WINDOW_CHANGE_DEBOUNCE_MS) // 等待指定的防抖时间

                            val currentGlobalPageIdAfterDelay = MyAccessibilityService.currentPageId
                            if (activeServiceInstance?.get() == null ||
                                            currentGlobalPageIdAfterDelay != pageIdForDebounce
                            ) {
                                // "窗口状态变更：对于页面 $pageIdForDebounce，延迟后上下文已更改或服务非活动状态。当前全局页面:
                                // $currentGlobalPageIdAfterDelay。跳过处理。"
                                return@launch
                            }

                            val collectedNodesForThisEvent = mutableListOf<NodeData>()

                            val rootNode = rootInActiveWindow

                            if (rootNode != null) {

                                traverseAndCollect(rootNode, collectedNodesForThisEvent)
                                // 注意: rootInActiveWindow 不需要显式回收。
                            } else {
                                // "窗口状态变更：防抖后页面 $pageIdForDebounce 的根节点为 null。跳过处理。"
                                return@launch // 如果无法获取根节点，则中止
                            }

                            // 检查页面ID是否有效，以及是否收集到了节点
                            if (isValidPageId(pageIdForDebounce)) {
                                if (collectedNodesForThisEvent.isNotEmpty()) {

                                    processCollectedNodes(
                                            pageIdForDebounce,
                                            ArrayList(collectedNodesForThisEvent)
                                    )
                                } else {
                                    // "窗口状态变更：防抖后未为页面 $pageIdForDebounce 收集到节点，跳过处理。"
                                }
                            } else {
                                // "窗口状态变更：防抖后无效的 PageId '$pageIdForDebounce'，跳过处理。"
                            }
                        }
                        .also { job ->
                            // 当协程任务完成时（无论是正常结束还是被取消），将其从映射中移除
                            job.invokeOnCompletion { throwable ->
                                if (throwable is CancellationException) {
                                    // "窗口状态变更：页面 $pageIdForDebounce 的防抖任务已被取消。"
                                }
                                // 为防止竞态条件（例如，旧任务的完成回调在为同一pageId启动新任务后才执行），
                                // 仅当映射中存储的确实是当前这个job实例时才移除。
                                if (windowChangeDebounceJobs[pageIdForDebounce] == job) {
                                    windowChangeDebounceJobs.remove(pageIdForDebounce)
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
    private fun isValidPageId(pageId: String): Boolean {
        return pageId.isNotBlank() &&
                !pageId.contains(AppConstants.UNKNOWN_PACKAGE) &&
                !pageId.contains(AppConstants.UNKNOWN_CLASS)
    }

    private fun traverseAndCollect(
            node: AccessibilityNodeInfo?,
            collectedNodes: MutableList<NodeData>,
            visitedNodes: MutableSet<AccessibilityNodeInfo> = mutableSetOf() // 在单次遍历中去重
    ) {
        node ?: return

        if (!visitedNodes.add(node)) {
            return
        }

        node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { text ->
            collectedNodes.add(NodeData(node.windowId, node.viewIdResourceName, text))
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                traverseAndCollect(child, collectedNodes, visitedNodes)
            }
        }
    }

    private suspend fun processCollectedNodes(
            pageIdForProcessing: String,
            nodesToProcess: List<NodeData>
    ) =
            withContext(Dispatchers.IO) {
                if (!isValidPageId(pageIdForProcessing)) {
                    return@withContext
                }

                if (nodesToProcess.isEmpty()) {
                    return@withContext
                }

                val extractionResult = Extractor.extract(pageIdForProcessing, nodesToProcess)

                if (extractionResult != null) {
                    val (content, payment) = extractionResult
                    if (content != null || payment != null) {
                        saveIfNew(content, payment, pageIdForProcessing)
                    } else {
                        // "页面 '$pageIdForProcessing' 未提取到有效内容或支付信息。"
                    }
                } else {
                    // "提取器为页面 '$pageIdForProcessing' 返回 null。"
                }
            }

    private fun saveIfNew(content: String?, payment: String?, pageId: String) {
        if (content == null && payment == null) {
            // "页面 '$pageId' 内容和支付信息均为空，跳过保存。"
            return
        }

        val combinedDataForHash = "content:${content ?: "null"}|payment:${payment ?: "null"}"
        val currentHash = combinedDataForHash.hashCode()

        if (lastHashByPage[pageId] != currentHash) {
            lastHashByPage[pageId] = currentHash
            saveData(pageId, content, payment)
        } else {
            // "页面 '$pageId' 数据 (哈希: $currentHash) 重复，跳过保存。"
        }
    }

    private fun saveData(pageId: String, content: String?, payment: String?) {
        val (packageName, activityTitle) = parsePageId(pageId)

        if (packageName == AppConstants.UNKNOWN_PACKAGE ||
                        activityTitle == AppConstants.UNKNOWN_CLASS
        ) {
            // "无法从 PageId '$pageId' 解析有效的包名或活动名，取消保存。"
            return
        }

        val data =
                billData(
                        title = activityTitle,
                        content = content,
                        packageName = packageName,
                        postTime = System.currentTimeMillis(),
                        payment = payment
                )

        try {
            val json = Json.encodeToString(data)
            SharedPreferencesManager.getInstance(this).addBill(json)
        } catch (e: Exception) {}
    }

    private fun parsePageId(pageId: String): Pair<String, String> {
        val parts = pageId.split('/', limit = 2)
        val packageName =
                parts.getOrNull(0)?.takeIf { it.isNotEmpty() } ?: AppConstants.UNKNOWN_PACKAGE
        val activityTitle =
                parts.getOrNull(1)?.takeIf { it.isNotEmpty() } ?: AppConstants.UNKNOWN_CLASS
        return Pair(packageName, activityTitle)
    }

    override fun onInterrupt() {
        // contentChangeDebounceJobs.values.forEach { it.cancel() } // 取消所有待处理的防抖任务
        // contentChangeDebounceJobs.clear()
        windowChangeDebounceJobs.values.forEach { it.cancel("Service interrupted") }
        windowChangeDebounceJobs.clear()
        serviceScope.cancel()
        if (activeServiceInstance?.get() == this) {
            activeServiceInstance?.clear()
            activeServiceInstance = null
        }
    }

    override fun onDestroy() {
        //  contentChangeDebounceJobs.values.forEach { it.cancel() } // 取消所有待处理的防抖任务
        //  contentChangeDebounceJobs.clear()
        windowChangeDebounceJobs.values.forEach { it.cancel("Service destroyed") }
        windowChangeDebounceJobs.clear()
        serviceScope.cancel()
        if (activeServiceInstance?.get() == this) {
            activeServiceInstance?.clear()
            activeServiceInstance = null
        }
        super.onDestroy()
    }
}
