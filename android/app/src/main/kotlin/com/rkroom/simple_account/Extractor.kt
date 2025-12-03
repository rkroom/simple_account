package com.rkroom.simple_account

import timber.log.Timber

object Extractor {

    /**
     * @param pageIdentifier 封装了包名和类名的对象。
     * @param nodes 节点数据列表。
     * @param rules 经过预处理的规则Map，Key是包名，Value是该包对应的规则列表。
     */
    fun extract(
            pageIdentifier: PageIdentifier,
            nodes: List<NodeData>,
            matchedRule: ExtractionRule
    ): Pair<String?, String?>? {
        Timber.d("开始提取: pageId=$pageIdentifier, 节点数=${nodes.size}, 规则='${matchedRule.ruleName}'")

        // 依次尝试内容提取规则，直到成功或全部失败
        val extractedContent = extractTextByRules(nodes, matchedRule.contentRules)
        Timber.d("内容提取结果: '$extractedContent'")
        if (extractedContent == null && !matchedRule.continueOnContentFailure) {
            Timber.d("规则 '${matchedRule.ruleName}' 设置为 content 匹配失败后立即终止，跳过 payment 提取。")
            return null // 提前退出，避免额外开销
        }
        // 依次尝试支付方式提取规则
        val extractedPayment = extractTextByRules(nodes, matchedRule.paymentRules)
        Timber.d("支付方式提取结果: '$extractedPayment'")

        return if (extractedContent != null || extractedPayment != null) {
            Pair(extractedContent, extractedPayment).also {
                Timber.i("提取完成: content='${it.first}', payment='${it.second}'")
            }
        } else {
            Timber.d("提取完成: 未提取到任何有效信息。")
            null
        }
    }

    /** 遍历一组规则详情，按顺序尝试提取，成功一次即返回 */
    private fun extractTextByRules(nodes: List<NodeData>, ruleDetails: List<RuleDetail>): String? {
        if (ruleDetails.isEmpty()) return null
        Timber.d("尝试 ${ruleDetails.size} 条详细规则...")

        // 使用 withIndex() 来获取索引，以便判断是否为最后一条规则
        for ((index, ruleDetail) in ruleDetails.withIndex()) {
            Timber.d("正在尝试规则 #${index + 1}")

            // 判断当前规则是否是列表中的最后一条
            val isLastRuleInChain = (index == ruleDetails.size - 1)

            // 调用修改后的 applyRuleDetail 方法，并传入 isLastRuleInChain
            val result = applyRuleDetail(nodes, ruleDetail, isLastRuleInChain)

            // 只要 result 不是 null (意味着提取成功，或是在最后一条规则失败后返回了关键字)，就立即返回
            if (result != null) {
                Timber.d("规则 #${index + 1} 成功，结果: '$result'")
                return result
            }
        }

        Timber.d("所有详细规则均未提取到内容。")
        return null // 所有规则都尝试失败后，返回 null
    }

    /* 应用单条详细规则。*/
    private fun applyRuleDetail(
            nodes: List<NodeData>,
            ruleDetail: RuleDetail,
            isLastRule: Boolean
    ): String? {
        if (ruleDetail.keywords.isEmpty()) {
            return applyAbsoluteExtraction(nodes, ruleDetail.strategy)
        }

        val strategy = ruleDetail.strategy
        val useExactMatch = if (strategy is SimpleOffset) strategy.useExactMatch else false
        val keywordsSet = ruleDetail.keywordsSet

        Timber.d(
                "在 ${nodes.size} 个节点中搜索 ${keywordsSet.size} 个关键字 (精确匹配: $useExactMatch)，策略: ${strategy::class.simpleName}"
        )
        /*
        需缓存正则规则
        val regex = ruleDetail.combinedKeywordsRegex
        if (regex != null) {
            for ((idx, node) in nodes.withIndex()) {
                val matcher = regex.matcher(node.text)
                if (matcher.find()) { // 使用一次正则查找替代内层循环
                    val matchedKeyword = matcher.group(0) // 获取实际匹配到的那个关键字
                    Timber.d("在索引 $idx 处通过正则找到关键字 '$matchedKeyword'。应用策略...")
                    // ... 后续应用策略的逻辑
                }
            }
        }
        */
        for ((idx, node) in nodes.withIndex()) {
            // 查找匹配的关键字
            val matchedKeyword =
                    keywordsSet.firstOrNull { keyword ->
                        if (useExactMatch) {
                            node.text.equals(keyword, ignoreCase = true)
                        } else {
                            node.text.contains(keyword, ignoreCase = true)
                        }
                    }

            if (matchedKeyword != null) {
                Timber.d("在索引 $idx 处找到关键字 '$matchedKeyword'。应用策略...")

                // 应用提取策略 (相对定位：以 idx 为基准)
                val extractedText = applyStrategy(nodes, idx, strategy)

                if (extractedText != null) {
                    Timber.d("策略应用成功，提取文本: '$extractedText'")
                    return extractedText
                } else {
                    // 策略应用失败后的回退处理
                    if (isLastRule) {
                        Timber.d("找到关键字 '$matchedKeyword'，但策略应用失败。作为兜底返回关键字本身。")
                        return matchedKeyword
                    } else {
                        Timber.d("找到关键字 '$matchedKeyword'，但策略应用失败。继续尝试下一条规则...")
                        return null
                    }
                }
            }
        }

        Timber.d("遍历完所有节点后，未找到任何关键字。")
        return null
    }

    /** 处理无关键字的提取规则 (绝对定位模式) 将基准索引设为 0，使得 offset 代表列表中的绝对位置。 */
    private fun applyAbsoluteExtraction(
            nodes: List<NodeData>,
            strategy: ExtractionStrategy
    ): String? {
        Timber.d("应用绝对定位规则 (无关键字)，策略: ${strategy::class.simpleName}")

        // 如果节点列表为空，直接返回 null，防止后续处理异常
        if (nodes.isEmpty()) {
            Timber.d("节点列表为空，无法进行绝对定位提取。")
            return null
        }

        return applyStrategy(nodes, 0, strategy)
    }

    /** 根据不同的策略执行提取操作 */
    private fun applyStrategy(
            nodes: List<NodeData>,
            keywordIndex: Int,
            strategy: ExtractionStrategy
    ): String? {
        Timber.d("应用策略: ${strategy::class.simpleName}")

        val result =
                when (strategy) {
                    is SimpleOffset -> {
                        val targetIndex = keywordIndex + strategy.offset
                        Timber.d(
                                "SimpleOffset: 目标索引=$targetIndex (关键字索引=$keywordIndex + 偏移=${strategy.offset})"
                        )
                        nodes.getOrNull(targetIndex)?.text?.trim()?.takeIf { it.isNotBlank() }
                    }
                    is ConditionalOffset -> {
                        val checkIndex = keywordIndex + strategy.checkOffset
                        val targetIndex = keywordIndex + strategy.targetOffset
                        Timber.d(
                                "ConditionalOffset: 检查索引=$checkIndex, 目标索引=$targetIndex, 期望文本包含='${strategy.expectedTexts.joinToString()}'"
                        )

                        val checkNodeText = nodes.getOrNull(checkIndex)?.text?.trim() ?: ""

                        // 直接检查列表中是否有任意一个元素被包含
                        if (strategy.expectedTexts.any { expected ->
                                    checkNodeText.contains(expected, ignoreCase = true)
                                }
                        ) {
                            Timber.d("ConditionalOffset: 条件满足。")
                            nodes.getOrNull(targetIndex)?.text?.trim()?.takeIf { it.isNotBlank() }
                        } else {
                            Timber.d("ConditionalOffset: 条件不满足 (checkText='$checkNodeText').")
                            null
                        }
                    }
                    is Concatenate -> {
                        Timber.d("Concatenate: 拼接 ${strategy.parts.size} 个部分 。")
                        val concatenatedResult = buildString {
                            for (part in strategy.parts) {
                                when (part) {
                                    is Literal -> {
                                        Timber.d("拼接字面量: '${part.text}'")
                                        append(part.text)
                                    }
                                    is NodeText -> {
                                        val targetIndex = keywordIndex + part.offset
                                        val text =
                                                nodes.getOrNull(targetIndex)?.text?.trim()?.takeIf {
                                                    it.isNotBlank()
                                                }

                                        Timber.d("拼接节点文本: 索引=$targetIndex, 文本='$text'")
                                        // 如果 text 有效 (非null且非空白)，就拼接
                                        text?.let { append(it) }
                                    }
                                }
                            }
                        }
                        // 如果最终结果非空，则返回；否则返回 null
                        concatenatedResult.takeIf { it.isNotEmpty() }
                    }
                    is ExtractByViewId -> {
                        Timber.d("ExtractByViewId: 正在查找 ID '${strategy.viewId}'")

                        // 遍历所有节点，查找 ViewId 匹配的项
                        val targetNode =
                                nodes.firstOrNull { node ->
                                    val nodeId = node.viewId ?: return@firstOrNull false

                                    if (strategy.useExactMatch) {
                                        // 精确匹配：必须完全相等(com.pkg:id/name)
                                        nodeId == strategy.viewId
                                    } else {
                                        // 模糊匹配：结尾匹配
                                        nodeId.endsWith(strategy.viewId)
                                    }
                                }

                        if (targetNode != null) {
                            Timber.d("ExtractByViewId: 找到匹配节点，ID='${targetNode.viewId}'")
                        }

                        targetNode?.text?.trim()?.takeIf { it.isNotBlank() }
                    }
                    is DirectViewId -> {
                        Timber.d("DirectViewId: 正在全局查找 ID '${strategy.viewId}'")

                        val targetNode =
                                nodes.firstOrNull { node ->
                                    val nodeId = node.viewId ?: return@firstOrNull false
                                    if (strategy.useExactMatch) {
                                        nodeId == strategy.viewId
                                    } else {
                                        nodeId.endsWith(strategy.viewId)
                                    }
                                }

                        targetNode?.text?.trim()?.takeIf { it.isNotBlank() }
                    }
                }

        Timber.d("策略应用结果: '$result'")
        return result
    }
}
