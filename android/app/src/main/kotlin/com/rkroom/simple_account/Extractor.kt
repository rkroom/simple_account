package com.rkroom.simple_account

import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 纯数据节点快照，用于缓存 */
data class SnapshotNode(val text: String, val viewId: String?, val index: Int)

object Extractor {
    private const val TAG = "Extractor"

    /** 判断某条规则是否可以走 FastPath。 给外部（Service）用来判断是否需要创建 LazyNodeProvider。 */
    fun isFastPathRule(rule: ExtractionRule): Boolean = isEligibleForFastPath(rule)

    private fun shouldForceLazyDfs(rule: ExtractionRule): Boolean {
        fun isForce(s: ExtractionStrategy): Boolean = s is ExtractByViewId && !s.useExactMatch
        return rule.contentRules.any { isForce(it.strategy) } ||
                rule.paymentRules.any { isForce(it.strategy) }
    }

    suspend fun extract(
            pageIdentifier: PageIdentifier,
            root: AccessibilityNodeInfo,
            matchedRule: ExtractionRule,
            isContentChange: Boolean = false,
            isFinalAttempt: Boolean = true,
            sharedProvider: LazyNodeProvider? = null,
            disablePrefilter: Boolean = false,
    ): Pair<String?, String?>? =
            withContext(Dispatchers.Default) {
                if (root.packageName?.toString() != pageIdentifier.packageName)
                        return@withContext null
                AppLog.d {
                    "[$TAG][Rule=${matchedRule.ruleName}] 开始提取 | " +
                            "isContentChange=$isContentChange, isFinalAttempt=$isFinalAttempt"
                }
                val forceLazyDfs = shouldForceLazyDfs(matchedRule)

                // 通道选择
                if (isContentChange) {
                    if (!forceLazyDfs && isEligibleForFastPath(matchedRule)) {
                        AppLog.i {
                            "[$TAG][Rule=${matchedRule.ruleName}] 选择 FastPath (ContentChange)"
                        }
                        return@withContext extractFastPath(root, matchedRule)
                    }
                } else {
                    if (matchedRule.preFilterByKeywords && !disablePrefilter) {
                        AppLog.d { "[$TAG][Rule=${matchedRule.ruleName}] preFilterByKeywords 开始" }
                        val passed = preFilterBySystemApi(root, matchedRule)
                        if (!passed) {
                            AppLog.i {
                                "[$TAG][Rule=${matchedRule.ruleName}] preFilter 未命中任何关键词，终止"
                            }
                            return@withContext null
                        }
                        AppLog.d { "[$TAG][Rule=${matchedRule.ruleName}] preFilter 通过，强制 LazyDFS" }
                    } else if (!forceLazyDfs && isEligibleForFastPath(matchedRule)) {
                        AppLog.i {
                            "[$TAG][Rule=${matchedRule.ruleName}] 选择 FastPath (WindowState)"
                        }
                        return@withContext extractFastPath(root, matchedRule)
                    }
                }
                // LazyDFS 通道
                val nodeProvider = sharedProvider ?: LazyNodeProvider(root)
                val needRecycleProvider = (sharedProvider == null)
                AppLog.d { "[$TAG][Rule=${matchedRule.ruleName}] 进入常规通道 (Lazy DFS)" }

                val contentKeywords =
                        matchedRule.contentRules.flatMap { it.keywords }.filter { it.isNotBlank() }

                try {
                    var content: String? = null
                    for ((index, ruleDetail) in matchedRule.contentRules.withIndex()) {
                        AppLog.d {
                            "[$TAG][Rule=${matchedRule.ruleName}] Content#$index 执行策略: " +
                                    "${ruleDetail.strategy::class.simpleName}, keywords=${ruleDetail.keywords}"
                        }

                        val isLast = index == matchedRule.contentRules.size - 1

                        content =
                                executeStrategy(
                                        provider = nodeProvider,
                                        ruleDetail = ruleDetail,
                                        isLastRule = isLast,
                                        tagPrefix = "Content#$index",
                                        isFinalAttempt = isFinalAttempt
                                )

                        if (content != null) {
                            AppLog.i {
                                "[$TAG][Rule=${matchedRule.ruleName}] Content#$index 成功 -> $content"
                            }
                            break
                        } else {
                            AppLog.v { "[$TAG][Rule=${matchedRule.ruleName}] Content#$index 未命中" }
                        }
                    }

                    if (content == null) {
                        // DirectViewId 失败通常意味着页面结构完全不符，直接判为不命中
                        if (matchedRule.contentRules.any { it.strategy is DirectViewId }) {
                            AppLog.d {
                                "[$TAG][Rule=${matchedRule.ruleName}] Content DirectViewId 未命中，结束。"
                            }
                            return@withContext null
                        }

                        // 判断页面是否“出现过任何 Content 关键字”
                        var hasContentKeywordsInPage = false
                        if (contentKeywords.isNotEmpty()) {
                            hasContentKeywordsInPage =
                                    nodeProvider.findFirst { snapshot ->
                                        contentKeywords.any { kw ->
                                            snapshot.text.contains(kw, ignoreCase = true)
                                        }
                                    } != null
                        }

                        // 情况 A：完全没出现 Content 关键字
                        if (!hasContentKeywordsInPage) {
                            if (!matchedRule.continueOnContentFailure) {
                                AppLog.d { "[$TAG] Content 未命中关键字且不允许继续，结束。" }
                                return@withContext null
                            } else {
                                // 允许继续：仅 Payment
                                var payment: String? = null
                                for ((index, ruleDetail) in matchedRule.paymentRules.withIndex()) {
                                    val isLast = index == matchedRule.paymentRules.size - 1
                                    payment =
                                            executeStrategy(
                                                    provider = nodeProvider,
                                                    ruleDetail = ruleDetail,
                                                    isLastRule = isLast,
                                                    tagPrefix = "Payment#$index",
                                                    isFinalAttempt = isFinalAttempt
                                            )
                                    if (payment != null) {
                                        AppLog.d { "[$TAG] Payment提取成功(仅Payment): $payment" }
                                        break
                                    }
                                }
                                return@withContext if (payment != null) Pair(null, payment)
                                else null
                            }
                        }

                        // 情况 B：出现了关键字，但提取失败
                        if (!matchedRule.continueOnContentFailure) {
                            AppLog.d { "[$TAG] Content提取失败但命中关键字，生成空账单。" }
                            return@withContext Pair("", null)
                        } else {
                            AppLog.d { "[$TAG] Content提取失败但命中关键字，继续尝试 Payment。" }
                            var payment: String? = null
                            for ((index, ruleDetail) in matchedRule.paymentRules.withIndex()) {
                                val isLast = index == matchedRule.paymentRules.size - 1
                                payment =
                                        executeStrategy(
                                                provider = nodeProvider,
                                                ruleDetail = ruleDetail,
                                                isLastRule = isLast,
                                                tagPrefix = "Payment#$index",
                                                isFinalAttempt = isFinalAttempt
                                        )
                                if (payment != null) {
                                    AppLog.d { "[$TAG] Payment提取成功: $payment" }
                                    break
                                }
                            }
                            return@withContext Pair("", payment)
                        }
                    }

                    var payment: String? = null
                    if (matchedRule.paymentRules.isNotEmpty()) {
                        for ((index, ruleDetail) in matchedRule.paymentRules.withIndex()) {
                            val isLast = index == matchedRule.paymentRules.size - 1
                            payment =
                                    executeStrategy(
                                            provider = nodeProvider,
                                            ruleDetail = ruleDetail,
                                            isLastRule = isLast,
                                            tagPrefix = "Payment#$index",
                                            isFinalAttempt = isFinalAttempt
                                    )
                            if (payment != null) {
                                AppLog.d { "[$TAG] Payment提取成功: $payment" }
                                break
                            }
                        }
                    }

                    return@withContext if (content != null || payment != null)
                            Pair(content, payment)
                    else null
                } catch (e: Exception) {
                    AppLog.e(e) { "[$TAG] 提取异常" }
                    null
                } finally {
                    if (needRecycleProvider) nodeProvider.recycle()
                }
            }

    /** WindowStateChanged 下的 preFilter：系统API预检任意关键词命中即通过 */
    private fun preFilterBySystemApi(root: AccessibilityNodeInfo, rule: ExtractionRule): Boolean {
        val allKeywords =
                (rule.contentRules + rule.paymentRules)
                        .flatMap { it.keywords }
                        .map { it.trim() }
                        .filter { it.isNotEmpty() }

        // 没配置关键词：无法预检，视为放行
        if (allKeywords.isEmpty()) return true

        for (kw in allKeywords) {
            val nodes =
                    try {
                        root.findAccessibilityNodeInfosByText(kw)
                    } catch (_: Exception) {
                        null
                    }
            if (!nodes.isNullOrEmpty()) {
                nodes.recycleAll()
                AppLog.v { "[$TAG] preFilterByKeywords 命中关键词: $kw" }
                return true
            }
            nodes.recycleAll()
        }
        return false
    }

    private fun isEligibleForFastPath(rule: ExtractionRule): Boolean {
        fun isStrategyEligible(strategy: ExtractionStrategy): Boolean =
                when (strategy) {
                    is DirectViewId -> true
                    is ExtractByViewId -> strategy.useExactMatch
                    is SimpleOffset -> strategy.offset == 0 && !strategy.useExactMatch
                    else -> false
                }

        return rule.contentRules.all { isStrategyEligible(it.strategy) } &&
                rule.paymentRules.all { isStrategyEligible(it.strategy) }
    }
    /**
     * FastPath：系统 API 快速提取通道。
     *
     * 仅支持以下简单策略：
     * - DirectViewId
     * - ExtractByViewId(useExactMatch = true)
     * - SimpleOffset(offset = 0, useExactMatch = false)
     *
     * FastPath 不遍历整棵节点树，不支持 offset、条件判断、文本拼接、 非精准 ViewId 后缀匹配，也不负责 LazyDFS 通道中的复杂失败语义。
     *
     * 特别注意： FastPath 不处理“Content 关键字出现但目标值提取失败时生成空账单”的逻辑。 对于依赖该语义的规则，应让规则走 LazyDFS。
     */
    private fun extractFastPath(
            root: AccessibilityNodeInfo,
            rule: ExtractionRule
    ): Pair<String?, String?>? {
        AppLog.d { "[$TAG][Rule=${rule.ruleName}] FastPath 执行" }
        fun getBySystemApi(rules: List<RuleDetail>, type: String): String? {
            for (detail in rules) {
                val strategy = detail.strategy
                AppLog.v {
                    "[$TAG][FastPath-$type] 尝试策略 ${strategy::class.simpleName} " +
                            "keywords=${detail.keywords}"
                }
                try {
                    val nodes =
                            when (strategy) {
                                is DirectViewId ->
                                        root.findAccessibilityNodeInfosByViewId(strategy.viewId)
                                is ExtractByViewId -> // useExactMatch=true
                                root.findAccessibilityNodeInfosByViewId(strategy.viewId)
                                is SimpleOffset -> { // offset=0 && exact=false
                                    var found: List<AccessibilityNodeInfo>? = null
                                    for (kw in detail.keywords) {
                                        val res = root.findAccessibilityNodeInfosByText(kw)
                                        if (!res.isNullOrEmpty()) {
                                            found = res
                                            break
                                        }
                                    }
                                    found
                                }
                                else -> null
                            }

                    if (!nodes.isNullOrEmpty()) {
                        var resultText: String? = null
                        for (node in nodes) {
                            if (isVisible(node)) {
                                val raw = node.text?.toString()?.trim()
                                val desc = node.contentDescription?.toString()?.trim()
                                val text = if (!raw.isNullOrEmpty()) raw else desc
                                if (!text.isNullOrEmpty()) {
                                    resultText = text
                                    break
                                }
                            }
                        }
                        nodes.recycleAll()
                        if (resultText != null) {
                            AppLog.v { "[$TAG] FastPath($type) 命中: $resultText" }
                            return resultText
                        }
                    }
                } catch (_: Exception) {
                    AppLog.w { "[$TAG] FastPath 系统API查找失败" }
                }
            }
            return null
        }

        val content = getBySystemApi(rule.contentRules, "Content")
        if (content == null && !rule.continueOnContentFailure) return null
        val payment = getBySystemApi(rule.paymentRules, "Payment")
        return if (content != null || payment != null) Pair(content, payment) else null
    }

    private fun executeStrategy(
            provider: LazyNodeProvider,
            ruleDetail: RuleDetail,
            isLastRule: Boolean,
            tagPrefix: String,
            isFinalAttempt: Boolean
    ): String? {
        val strategy = ruleDetail.strategy

        AppLog.v {
            "[$TAG][$tagPrefix] 执行策略 ${strategy::class.simpleName} | " +
                    "keywords=${ruleDetail.keywords}, isLast=$isLastRule, final=$isFinalAttempt"
        }
        val hasKeywords = ruleDetail.keywords.isNotEmpty()

        fun isMatch(node: SnapshotNode): Boolean =
                ruleDetail.keywords.any { k ->
                    if (k.isBlank()) return@any false
                    if (strategy is SimpleOffset && strategy.useExactMatch)
                            node.text.equals(k, ignoreCase = true)
                    else node.text.contains(k, ignoreCase = true)
                }

        return when (strategy) {
            is DirectViewId -> {
                AppLog.v { "[$TAG][$tagPrefix] DirectViewId 查找: ${strategy.viewId}" }
                val res = provider.findById(strategy.viewId, exact = true)
                if (res != null) {
                    AppLog.i { "[$TAG][$tagPrefix] DirectViewId 命中 -> $res" }
                }
                res
            }
            is ExtractByViewId -> {
                AppLog.v {
                    "[$TAG][$tagPrefix] ExtractByViewId 查找: ${strategy.viewId}, exact=${strategy.useExactMatch}"
                }

                val textById = provider.findById(strategy.viewId, exact = strategy.useExactMatch)
                if (!textById.isNullOrBlank()) {
                    AppLog.i { "[$TAG][$tagPrefix] ExtractByViewId 命中 -> $textById" }
                    return textById
                }

                if (!strategy.useExactMatch && isLastRule && hasKeywords && isFinalAttempt) {
                    val fallbackNode = provider.findFirst { isMatch(it) }

                    if (fallbackNode != null) {
                        val fallbackText = fallbackNode.text
                        if (fallbackText.isNotBlank()) {
                            AppLog.w { "[$TAG][$tagPrefix] ID 未命中，关键词兜底 -> $fallbackText" }
                            return fallbackText
                        }
                    }
                }

                null
            }
            is SimpleOffset, is ConditionalOffset, is Concatenate -> {
                if (!hasKeywords) {
                    AppLog.w { "[$TAG] $tagPrefix 策略${strategy::class.simpleName}必须配置关键字" }
                    return null
                }
                val anchorNode = provider.findFirst { isMatch(it) }
                if (anchorNode == null) {
                    AppLog.v { "[$TAG][$tagPrefix] 未找到锚点节点" }
                    return null
                }

                AppLog.v {
                    "[$TAG][$tagPrefix] 锚点命中: index=${anchorNode.index}, text=${anchorNode.text}"
                }
                val result =
                        when (strategy) {
                            is SimpleOffset -> {
                                val targetIndex = anchorNode.index + strategy.offset
                                AppLog.v {
                                    "[$TAG][$tagPrefix] SimpleOffset offset=${strategy.offset}, targetIndex=$targetIndex"
                                }
                                provider.getByIndex(targetIndex)?.text
                            }
                            is ConditionalOffset -> {
                                val checkIndex = anchorNode.index + strategy.checkOffset
                                val checkNode = provider.getByIndex(checkIndex)
                                AppLog.v {
                                    "[$TAG][$tagPrefix] ConditionalOffset checkIndex=$checkIndex, text=${checkNode?.text}"
                                }

                                if (checkNode != null &&
                                                strategy.expectedTexts.any {
                                                    checkNode.text.contains(it)
                                                }
                                ) {
                                    val targetIndex = anchorNode.index + strategy.targetOffset
                                    AppLog.v { "[$TAG][$tagPrefix] 条件满足，targetIndex=$targetIndex" }
                                    provider.getByIndex(targetIndex)?.text
                                } else null
                            }
                            is Concatenate -> {
                                AppLog.v {
                                    "[$TAG][$tagPrefix] Concatenate parts=${strategy.parts}"
                                }
                                buildConcatenateString(provider, strategy, anchorNode.index)
                            }
                            else -> null
                        }

                if (!result.isNullOrBlank()) return result

                if (isLastRule && isFinalAttempt) {
                    val fallback = anchorNode.text
                    AppLog.d { "[$TAG] $tagPrefix 提取失败，触发兜底返回节点文本/描述: $fallback" }
                    return fallback
                }
                null
            }
        }
    }

    private fun buildConcatenateString(
            provider: LazyNodeProvider,
            strategy: Concatenate,
            baseIndex: Int
    ): String? {
        val sb = StringBuilder()
        var hasNode = false
        for (part in strategy.parts) {
            when (part) {
                is Literal -> sb.append(part.text)
                is NodeText -> {
                    val text = provider.getByIndex(baseIndex + part.offset)?.text
                    if (text != null) {
                        sb.append(text)
                        hasNode = true
                    }
                }
            }
        }
        return if (hasNode) sb.toString() else null
    }

    private fun isVisible(node: AccessibilityNodeInfo): Boolean =
            try {
                node.isVisibleToUser
            } catch (_: Exception) {
                false
            }

    private fun List<AccessibilityNodeInfo>?.recycleAll() {
        this?.forEach {
            try {
                it.recycle()
            } catch (_: Exception) {}
        }
    }

    class LazyNodeProvider(root: AccessibilityNodeInfo) {
        private val cachedNodes = ArrayList<SnapshotNode>()
        private val stack = ArrayDeque<AccessibilityNodeInfo>()
        private val rootRef = root
        private var visitedCount = 0

        companion object {
            private const val MAX_TRAVERSAL_LIMIT = 300
        }

        init {
            try {
                stack.push(root)
            } catch (_: Exception) {}
        }

        fun getByIndex(index: Int): SnapshotNode? {
            if (index < 0) return null
            while (cachedNodes.size <= index &&
                    stack.isNotEmpty() &&
                    visitedCount < MAX_TRAVERSAL_LIMIT) advance()
            return if (index < cachedNodes.size) cachedNodes[index] else null
        }

        fun findFirst(predicate: (SnapshotNode) -> Boolean): SnapshotNode? {
            for (n in cachedNodes) if (predicate(n)) return n
            while (stack.isNotEmpty() && visitedCount < MAX_TRAVERSAL_LIMIT) {
                val nn = advance()
                if (nn != null && predicate(nn)) return nn
            }
            return null
        }

        fun findById(viewId: String, exact: Boolean): String? {
            if (viewId.isBlank()) return null
            return findFirst {
                        val id = it.viewId ?: return@findFirst false
                        if (exact) id == viewId else id.endsWith(viewId)
                    }
                    ?.text
        }

        private fun advance(): SnapshotNode? {
            if (stack.isEmpty()) return null
            if (visitedCount >= MAX_TRAVERSAL_LIMIT) {
                if (visitedCount == MAX_TRAVERSAL_LIMIT) {
                    AppLog.w { "[$TAG] 遍历触发熔断机制: 已扫描 $MAX_TRAVERSAL_LIMIT 个节点" }
                    visitedCount++
                }
                return null
            }
            visitedCount++
            val node = stack.pop()
            var snapshot: SnapshotNode? = null
            try {
                if (isVisible(node)) {
                    val raw = node.text?.toString()?.trim()
                    val desc = node.contentDescription?.toString()?.trim()
                    val effective = if (!raw.isNullOrEmpty()) raw else desc
                    if (!effective.isNullOrEmpty()) {
                        snapshot =
                                SnapshotNode(effective, node.viewIdResourceName, cachedNodes.size)
                        cachedNodes.add(snapshot)
                    }
                    val count = node.childCount
                    for (i in count - 1 downTo 0) {
                        node.getChild(i)?.let { stack.push(it) }
                    }
                }
            } catch (_: Exception) {} finally {
                if (node != rootRef) {
                    try {
                        node.recycle()
                    } catch (_: Exception) {}
                }
            }
            return snapshot
        }

        fun recycle() {
            while (stack.isNotEmpty()) {
                val n = stack.pop()
                if (n != rootRef) {
                    try {
                        n.recycle()
                    } catch (_: Exception) {}
                }
            }
            cachedNodes.clear()
        }
    }
}

@OptIn(ExperimentalContracts::class)
inline fun <R> AccessibilityNodeInfo.use(block: (AccessibilityNodeInfo) -> R): R {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    try {
        return block(this)
    } finally {
        try {
            this.recycle()
        } catch (_: Exception) {}
    }
}
