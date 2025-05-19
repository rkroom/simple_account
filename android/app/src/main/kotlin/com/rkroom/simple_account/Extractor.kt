package com.rkroom.simple_account

object Extractor {
    fun extract(pageId: String, nodes: List<NodeData>): Pair<String?, String?>? {
        val packageName = pageId.substringBeforeLast('/', "")

        val result =
                when (packageName) {
                    AppConstants.PACKAGE_JD -> {
                        ExtractorJd.extract(pageId, nodes)
                    }
                    AppConstants.PACKAGE_ALIPAY -> {
                        ExtractorAlipay.extract(pageId, nodes)
                    }
                    AppConstants.PACKAGE_WECHAT -> {
                        ExtractorWeChat.extract(pageId, nodes)
                    }
                    else -> {
                        null
                    }
                }
        return result
    }
}

object ExtractorJd {
    fun extract(pageId: String, nodes: List<NodeData>): Pair<String?, String?>? {
        if (!pageId.endsWith(AppConstants.ACTIVITY_JD_CASHIER_COMPLETE)) {
            return null
        }

        val idx = nodes.indexOfFirst { it.text == AppConstants.KEYWORD_PAYMENT_SUCCESS }

        if (idx < 0) {
            return null
        }

        if (idx + 1 < nodes.size) {
            val textToAppend = nodes[idx + 1].text.trim()
            return if (textToAppend.isNotBlank()) {
                val result = Pair(textToAppend, null)
                result
            } else {
                null
            }
        } else {
            return null
        }
    }
}

object ExtractorAlipay {
    fun extract(pageId: String, nodes: List<NodeData>): Pair<String?, String?>? {
        var extractedContent: String? = null
        var extractedPayment: String? = null

        if (pageId.endsWith(AppConstants.ACTIVITY_ALIPAY_NRESPAGE)) {
            val successIdx =
                    nodes.indexOfFirst { it.text.contains(AppConstants.KEYWORD_PAYMENT_SUCCESS) }

            if (successIdx != -1) {
                val targetNodeIndex = successIdx + 3
                if (targetNodeIndex < nodes.size) {
                    val contentNodeText = nodes[targetNodeIndex].text.trim()
                    if (contentNodeText.isNotBlank()) {
                        extractedContent = contentNodeText
                    }
                }
            }

            val paymentMethodIdx =
                    nodes.indexOfFirst {
                        it.text.contains(AppConstants.KEYWORD_TRANSACTION_METHOD_ALIPAY_1) ||
                                it.text.contains(AppConstants.KEYWORD_TRANSACTION_METHOD_ALIPAY_2)
                    }

            if (paymentMethodIdx != -1) {
                if (paymentMethodIdx + 1 < nodes.size) {
                    val methodValue = nodes[paymentMethodIdx + 1].text.trim()
                    if (methodValue.isNotBlank()) {
                        extractedPayment = methodValue
                    }
                }
            }
        } else if (pageId.endsWith(AppConstants.ACTIVITY_ALIPAY_MSP_CONTAINER)) {
            val successIdx =
                    nodes.indexOfFirst { it.text.contains(AppConstants.KEYWORD_PAYMENT_SUCCESS) }

            if (successIdx >= 0) {
                if (successIdx + 2 < nodes.size &&
                                nodes[successIdx + 1].text.trim() ==
                                        AppConstants.CURRENCY_SYMBOL_CNY
                ) {
                    val amount = nodes[successIdx + 2].text.trim()
                    if (amount.isNotBlank()) {
                        extractedContent =
                                "${nodes[successIdx].text.trim()} ${AppConstants.CURRENCY_SYMBOL_CNY}$amount"
                    }
                }

                if (extractedContent == null && successIdx + 1 < nodes.size) {
                    val nextNodeText = nodes[successIdx + 1].text.trim()
                    if (nextNodeText.isNotBlank() &&
                                    !nextNodeText.startsWith(AppConstants.CURRENCY_SYMBOL_CNY)
                    ) {
                        extractedContent = "${nodes[successIdx].text.trim()} $nextNodeText"
                    } else if (nextNodeText.isNotBlank() &&
                                    nextNodeText.startsWith(AppConstants.CURRENCY_SYMBOL_CNY) &&
                                    successIdx + 2 >= nodes.size
                    ) {
                        extractedContent = "${nodes[successIdx].text.trim()} $nextNodeText"
                    }
                } else if (extractedContent == null) {
                    extractedContent = nodes[successIdx].text.trim()
                }
            }

            val paymentMethodIdx =
                    nodes.indexOfFirst {
                        it.text.contains(AppConstants.KEYWORD_TRANSACTION_METHOD_ALIPAY_1) ||
                                it.text.contains(AppConstants.KEYWORD_TRANSACTION_METHOD_ALIPAY_2)
                    }

            if (paymentMethodIdx != -1) {
                if (paymentMethodIdx + 1 < nodes.size) {
                    val methodValue = nodes[paymentMethodIdx + 1].text.trim()
                    if (methodValue.isNotBlank()) {
                        extractedPayment = "${nodes[paymentMethodIdx].text.trim()}: $methodValue"
                    }
                } else {
                    extractedPayment = nodes[paymentMethodIdx].text.trim()
                }
            }
        } else {
            return null
        }

        return if (extractedContent != null || extractedPayment != null) {
            val result = Pair(extractedContent, extractedPayment)
            result
        } else {
            null
        }
    }
}

object ExtractorWeChat {
    fun extract(pageId: String, nodes: List<NodeData>): Pair<String?, String?>? {
        if (!pageId.endsWith(AppConstants.ACTIVITY_WECHAT_UIPAGEFRAGMENT)) {
            return null
        }

        val successIdx =
                nodes.indexOfFirst {
                    it.text == AppConstants.KEYWORD_PAYMENT_SUCCESS
                } 

        if (successIdx == -1) {
            return null
        }

        val targetNodeIndex = successIdx + 2

        if (targetNodeIndex < nodes.size) {
            val contentNodeText = nodes[targetNodeIndex].text.trim()
            return if (contentNodeText.isNotBlank()) {
                val result = Pair(contentNodeText, null)
                result
            } else {
                null
            }
        } else {
            return null
        }
    }
}
