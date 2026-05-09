package com.rkroom.simple_account

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import io.flutter.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

enum class AppLogLevel(val priority: Int) {
        VERBOSE(Log.VERBOSE),
        DEBUG(Log.DEBUG),
        INFO(Log.INFO),
        WARN(Log.WARN),
        ERROR(Log.ERROR),
        OFF(Int.MAX_VALUE); // 关闭日志 (优先级设为最大整数，任何日志都无法通过)

        companion object {
                val DEFAULT = OFF

                /** 通过 Int 值查找对应的枚举，用于从 DataStore 恢复状态 如果找不到对应值，默认返回 OFF，防止崩溃 */
                fun fromPriority(priority: Int): AppLogLevel {
                        return entries.find { it.priority == priority } ?: DEFAULT
                }
        }
}

object AppLogConfig {

        @Volatile var currentLogLevel: Int = AppLogLevel.DEFAULT.priority

        /** 快速判断是否需要执行日志逻辑 */
        fun isLoggable(priority: Int): Boolean {
                val current = currentLogLevel
                if (current == AppLogLevel.OFF.priority) return false
                return priority >= current
        }
}

// 获取 DataStore 实例
private val Context.configDataStore: DataStore<Preferences> by
        preferencesDataStore(name = "ConfigPreferences")

@Serializable
data class PackageConfigItem(val packageName: String, val appName: String, val isAllowed: Boolean)
/** 辅助功能服务配置 */
data class ServiceConfig(
        val allowedPackageNames: Set<String>,
        val extractionRules: Map<String, List<ExtractionRule>>,
        val windowChangeDebounceMs: Long,
        val contentChangeDebounceMs: Long,
        val isContentChangeEnabled: Boolean,
)

/** 通知监听服务配置 */
data class NotificationConfig(
        val allowedPackages: Set<String>, // 使用 Set 优化查找
        val keywords: List<String>
)

/** 提取策略的密封接口 */
@Serializable sealed interface ExtractionStrategy

/**
 * 策略: 简单偏移量提取
 *
 * - 配合 RuleDetail.keywords 使用，以第一个匹配到关键字的节点作为“锚点”。
 * - offset 表示在同一棵树经 DFS 扁平化后的相对偏移量：0 表示锚点本身，1 表示下一个可见文本节点，以此类推。
 * - useExactMatch = true 时，关键字匹配要求 node.text 与关键字完全相等（忽略大小写）； 否则只要求包含关系（contains，忽略大小写）。
 * - 当 offset == 0 且 useExactMatch == false 时，该规则直接用系统 API 根据文本查找节点。
 *
 * 注意：
 * - 在通用 DFS 通道下，如果 keywords 为空，则该策略不会生效（找不到锚点）。
 */
@Serializable
@SerialName("SimpleOffset")
data class SimpleOffset(val offset: Int, val useExactMatch: Boolean = false) : ExtractionStrategy

/**
 * 策略: 条件偏移量提取
 *
 * 典型场景：关键字节点附近有 “￥ / ¥” 等金额符号，通过条件节点判断再取目标金额。
 *
 * - 先和 SimpleOffset 一样，通过 keywords 找到锚点节点（第一个匹配关键字的节点）。
 * - checkOffset：相对于锚点的偏移，用于定位“条件节点”。
 * - expectedTexts：条件节点文本中需要包含的任意字符串列表（例如 ["¥", "￥"]）。
 * - targetOffset：当条件节点满足 expectedTexts 时，才根据这个偏移取出目标节点文本。
 *
 * 注意：
 * - 同样依赖 RuleDetail.keywords 先找到锚点；如果 keywords 为空则不会生效。
 */
@Serializable
@SerialName("ConditionalOffset")
data class ConditionalOffset(
        val checkOffset: Int,
        val expectedTexts: List<String>,
        val targetOffset: Int
) : ExtractionStrategy

/**
 * 策略: 文本拼接
 *
 * - 在常规提取流程中（非 triggerOnEmptyNodes），Concatenate 依赖 RuleDetail.keywords 找到一个锚点节点，然后根据
 * NodeText(offset) 从锚点附近的节点中取文本，再和 Literal 文本拼接。
 * - offset 为相对锚点的偏移（同 SimpleOffset/ConditionalOffset）。
 *
 * 特殊行为：
 * - 当 ExtractionRule.triggerOnEmptyNodes = true 且 contentRules 中存在仅由 Literal 组成的 Concatenate（没有
 * NodeText），在进入页面时会被视为“静态文案”，直接拼接为一个固定字符串 作为 content 写入账单（不依赖任何节点文本）。
 *
 * 注意：
 * - 在常规 DFS 通道下，包含 NodeText 的 Concatenate 仍然需要 keywords 来定位锚点， keywords 为空时不会生效。
 */
@Serializable
@SerialName("Concatenate")
data class Concatenate(val parts: List<ConcatPart>) : ExtractionStrategy

/**
 * 策略: 指定 View ID。
 *
 * 注意：必须提供完整的 Resource ID (例如 "pkgname:id/viewid")。无视keywords。
 * - 直接调用系统 API findAccessibilityNodeInfosByViewId。
 */
@Serializable
@SerialName("DirectViewId")
data class DirectViewId(val viewId: String) : ExtractionStrategy

/**
 * 策略: 通过 View ID 提取文本
 * @param viewId 目标控件的 ID
 * @param useExactMatch 是否需要完全匹配 (true: 必须包含包名; false: 只要 ID 后缀匹配即可)
 *
 * 注意：
 * - 当 useExactMatch = false 且该 RuleDetail 是所在列表中的最后一条规则时， 如果通过 viewId 未找到节点，并且配置了 keywords，
 * 则会退回到关键字查找：仅当页面中存在匹配关键字的节点时，返回该节点文本。
 */
@Serializable
@SerialName("ExtractByViewId")
data class ExtractByViewId(val viewId: String, val useExactMatch: Boolean = false) :
        ExtractionStrategy

/** 定义拼接的各个部分 */
@Serializable sealed interface ConcatPart

@Serializable
@SerialName("Literal")
data class Literal(val text: String) : ConcatPart // 静态文本

@Serializable
@SerialName("NodeText")
data class NodeText(val offset: Int) : ConcatPart // 动态节点文本

/** 包含了关键字和具体执行策略的详细规则 */
// 仅对匹配到的第一个关键词处理，需要小心处理关键词
@Serializable data class RuleDetail(val keywords: List<String>, val strategy: ExtractionStrategy)

/*
@Serializable
data class RuleDetail(
    val keywords: List<String>,
    val strategy: ExtractionStrategy
) {
    @Transient // 这个字段不需要被序列化，它是在运行时计算的
    val combinedKeywordsRegex: Pattern? = if (keywords.isNotEmpty()) {
        // 编译为正则表达式
        Pattern.compile(keywords.joinToString("|"), Pattern.CASE_INSENSITIVE)
    } else {
        null
    }
}
*/

/** 针对一个页面的顶层提取规则 contentRules 和 paymentRules 改为List，用于实现回退逻辑 */
@Serializable
data class ExtractionRule(
        /** 规则名称。 */
        val ruleName: String,

        /** 目标应用的包名。 */
        val packageName: String,

        /** 目标页面的 Activity 类名。 支持后缀匹配 (endsWith)"。 */
        val activityName: String,

        /** 金额/主要内容的提取规则列表。 这是一个 List，按顺序执行，支持回退机制 (Fallback)。 如果第一个规则提取失败，会尝试第二个，直到成功或列表结束。 */
        val contentRules: List<RuleDetail>,

        /** 支付方式的提取规则列表。 同样支持 List 回退机制。 */
        val paymentRules: List<RuleDetail>,

        /**
         * 当金额 (Content) 提取失败时，是否继续提取支付方式。
         * - true : 继续尝试提取支付方式 (用于调试或特殊需求)。
         * - false(默认)：直接中止本次提取，视为失败（但是在Content的关键词存在时依然生成空白账单）。
         */
        val continueOnContentFailure: Boolean = false,

        /** 进入页面则直接记录。 默认 false。 */
        val triggerOnEmptyNodes: Boolean = false,

        /**
         * triggerOnEmptyNodes 的冷却时间 (毫秒)。 默认 120000ms (2分钟)。
         * - 同一页面 (包名 + 类名) 下，任意一条 triggerOnEmptyNodes 规则成功触发时， 都会刷新该页面的“最近触发时间”，从而影响该页面中所有
         * EmptyNode 规则的冷却判断。
         * - 如果 > 0: 在冷却时间内，同一个页面只有第一次触发会记录，后续的 EmptyNode 规则都会被忽略。
         * - 如果 = 0: 每一个新的 WindowID 都会记录一次 (即每次进入页面都记)。
         */
        val emptyNodeTriggerCooldownMs: Long = 120000L,

        /**
         * 是否启用关键字预过滤。
         *
         * 注意：
         * * preFilterByKeywords = true 时，会先做一次全局关键字扫描，用于快速判定“页面是否值得继续提取”。
         * * 在 TYPE_WINDOW_CONTENT_CHANGED 时，该配置不起作用。
         * - 如果同一页面中存在 ExtractByViewId(useExactMatch = false) 的规则， 为了避免多余IPC调用，会关闭该页面所有规则的关键字预过滤。
         */
        val preFilterByKeywords: Boolean = false,

        /** 是否允许 `TYPE_WINDOW_CONTENT_CHANGED` 事件触发此规则。 */
        val allowContentChangeTrigger: Boolean = false,

        /** 该页面是否包含支付方式信息（影响提取时更新记录） 。 */
        val hasPaymentInfo: Boolean = true,

        /** 最大内容变更触发次数。 默认值设为 2 。多条规则取最大值 */
        val maxContentTriggerTimes: Int = 2,

        /** 动态页面提取失败后的重试次数 (主动轮询)。 0 = 关闭重试 (默认)。 多条规则取最大值 */
        val dynamicRetryTimes: Int = 0,
        /** 每次重试的间隔时间 (毫秒)。 配合 dynamicRetryTimes 使用。 默认 1000ms (1秒)。 多条规则取最大值 */
        val dynamicRetryIntervalMs: Long = 1000L
)

/**
 * 使用 DataStore-Preferences 管理应用配置 数据存放在
 * /data/data/<your.package>/files/datastore/ConfigPreferences.pb
 */
class ConfigDataStoreManager private constructor(context: Context) {
        private val context = context.applicationContext

        companion object :
                SingletonHolder<ConfigDataStoreManager, Context>({
                        ConfigDataStoreManager(it.applicationContext)
                }) {
                // 常量
                private val KEY_AB_PACKAGE_CONFIG = stringPreferencesKey("abPackageConfig")
                private val KEY_NL_PACKAGE_CONFIG = stringPreferencesKey("nlPackageConfig")
                private val KEY_NL_STATIC_KEYWORDS = stringPreferencesKey("nlKeywords")
                private val KEY_AB_EXTRACTION_RULES = stringPreferencesKey("abExtractionRules")
                private val KEY_LOG_LEVEL = intPreferencesKey("appLogLevel")
                private val KEY_WINDOW_CHANGE_DEBOUNCE_MS =
                        longPreferencesKey("windowChangeDebounceMs")
                private val KEY_CONTENT_CHANGE_DEBOUNCE_MS =
                        longPreferencesKey("contentChangeDebounceMs")
                private val KEY_ENABLE_WINDOW_CONTENT_CHANGE =
                        booleanPreferencesKey("enableWindowContentChange")
                private const val DEFAULT_WINDOW_CHANGE_DEBOUNCE_MS = 500L
                private const val DEFAULT_CONTENT_CHANGE_DEBOUNCE_MS = 500L
                private const val DEFAULT_ENABLE_WINDOW_CONTENT_CHANGE = false

                // 默认值
                private val DEFAULT_AB_PACKAGES_CONFIG: List<PackageConfigItem> =
                        listOf(
                                PackageConfigItem(
                                        packageName = "com.eg.android.AlipayGphone",
                                        appName = "支付宝",
                                        isAllowed = true
                                ),
                                /*
                                PackageConfigItem(
                                        packageName = "com.tencent.mm",
                                        appName = "微信",
                                        isAllowed = true
                                ),
                                */
                                PackageConfigItem(
                                        packageName = "com.jingdong.app.mall",
                                        appName = "京东",
                                        isAllowed = true
                                ),
                                PackageConfigItem(
                                        packageName = "com.taobao.taobao",
                                        appName = "淘宝",
                                        isAllowed = true
                                ),
                                PackageConfigItem(
                                        packageName = "com.tmall.wireless",
                                        appName = "天猫",
                                        isAllowed = true
                                ),
                        )
                private val DEFAULT_NL_PACKAGES_CONFIG: List<PackageConfigItem> =
                        listOf(
                                PackageConfigItem(
                                        packageName = "com.eg.android.AlipayGphone",
                                        appName = "支付宝",
                                        isAllowed = true
                                ),
                                PackageConfigItem(
                                        packageName = "com.tencent.mm",
                                        appName = "微信",
                                        isAllowed = true
                                )
                        )
                // 默认关键字
                private val DEFAULT_NL_KEYWORDS: List<String> = listOf("交易", "支付")
                // 默认提取规则
                private val DEFAULT_AB_EXTRACTION_RULES: List<ExtractionRule> =
                        listOf(
                                // 规则 1: 京东
                                ExtractionRule(
                                        ruleName = "JD Payment Success",
                                        packageName = "com.jingdong.app.mall",
                                        activityName =
                                                "com.jingdong.app.mall.bundle.cashierfinish.view.CashierUserContentCompleteActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("支付成功"),
                                                                strategy =
                                                                        SimpleOffset(
                                                                                offset = 1,
                                                                                useExactMatch = true
                                                                        )
                                                        )
                                                ),
                                        paymentRules = emptyList(),
                                        hasPaymentInfo = false
                                ),
                                /* 暂时无法获取具体信息，后期考虑OCR或者xposed hook
                                // 规则 2: 微信
                                ExtractionRule(
                                        ruleName = "WeChat Payment Success",
                                        packageName = "com.tencent.mm",
                                        activityName =
                                                "com.tencent.mm.framework.app.UIPageFragmentActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("支付成功"),
                                                                strategy =
                                                                        SimpleOffset(
                                                                                offset = 2,
                                                                                useExactMatch = true
                                                                        )
                                                        )
                                                ),
                                        paymentRules = emptyList(),
                                        preFilterByKeywords = true,
                                        hasPaymentInfo = false
                                ),
                                */
                                // 规则 3: 支付宝
                                ExtractionRule(
                                        ruleName = "Alipay NResPage",
                                        packageName = "com.eg.android.AlipayGphone",
                                        activityName =
                                                "com.alipay.android.phone.businesscommon.ucdp.nfc.activity.NResPageActivity",
                                        continueOnContentFailure = true,
                                        allowContentChangeTrigger = true,
                                        dynamicRetryTimes = 3,
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("支付成功"),
                                                                strategy =
                                                                        ExtractByViewId(
                                                                                viewId =
                                                                                        "com.alipay.mobile.ucdp:id/summary_amount_text",
                                                                                useExactMatch = true
                                                                        )
                                                        )
                                                ),
                                        paymentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("交易方式", "付款方式"),
                                                                strategy = SimpleOffset(offset = 1)
                                                        )
                                                )
                                ),
                                // 规则 4: 支付宝原生收银台
                                ExtractionRule(
                                        ruleName = "Alipay MspContainer",
                                        packageName = "com.eg.android.AlipayGphone",
                                        activityName =
                                                "com.alipay.android.msp.ui.views.MspContainerActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("支付成功", "转账成功"),
                                                                strategy =
                                                                        ConditionalOffset(
                                                                                checkOffset = 0,
                                                                                expectedTexts =
                                                                                        listOf(
                                                                                                "¥",
                                                                                                "￥"
                                                                                        ),
                                                                                targetOffset = 0
                                                                        )
                                                        ),
                                                        RuleDetail(
                                                                keywords = listOf("支付成功", "转账成功"),
                                                                strategy =
                                                                        ConditionalOffset(
                                                                                checkOffset = 1,
                                                                                expectedTexts =
                                                                                        listOf(
                                                                                                "¥",
                                                                                                "￥"
                                                                                        ),
                                                                                targetOffset = 2
                                                                        )
                                                        ),
                                                        RuleDetail(
                                                                keywords = listOf("支付成功", "转账成功"),
                                                                strategy = SimpleOffset(offset = 1)
                                                        )
                                                ),
                                        paymentRules =
                                                listOf(
                                                        // 拼接支付方式
                                                        RuleDetail(
                                                                keywords = listOf("交易方式", "付款方式"),
                                                                strategy =
                                                                        Concatenate(
                                                                                parts =
                                                                                        listOf(
                                                                                                NodeText(
                                                                                                        offset =
                                                                                                                0
                                                                                                ),
                                                                                                Literal(
                                                                                                        text =
                                                                                                                ": "
                                                                                                ),
                                                                                                NodeText(
                                                                                                        offset =
                                                                                                                1
                                                                                                )
                                                                                        )
                                                                        )
                                                        )
                                                ),
                                        continueOnContentFailure = true
                                ),
                                // 规则 5: 淘宝
                                ExtractionRule(
                                        ruleName = "Taobao Weex Trade Page",
                                        packageName = "com.taobao.taobao",
                                        activityName =
                                                "com.alibaba.android.ultron.vfw.weex2.highPerformance.widget.UltronTradeHybridActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = emptyList(),
                                                                strategy =
                                                                        Concatenate(
                                                                                parts =
                                                                                        listOf(
                                                                                                Literal(
                                                                                                        text =
                                                                                                                "淘宝交易页面(Weex)"
                                                                                                )
                                                                                        )
                                                                        )
                                                        )
                                                ),
                                        paymentRules = emptyList(),
                                        triggerOnEmptyNodes = true
                                ),
                                /*该规则目前无法获取到数据，或许以后采用截图OCR识别
                                // 规则 6: 淘宝闪购下单成功页面
                                ExtractionRule(
                                        ruleName = "Taobao Flash Shopping",
                                        packageName = "com.taobao.taobao",
                                        activityName =
                                                "com.taobao.themis.container.app.TMSActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("下单成功"),
                                                                strategy =
                                                                        SimpleOffset(
                                                                                offset = 0,
                                                                                useExactMatch =
                                                                                        false
                                                                        )
                                                        )
                                                ),
                                        paymentRules = emptyList(),
                                        continueOnContentFailure = false,
                                        triggerOnEmptyNodes = false,
                                        preFilterByKeywords = true,
                                        allowContentChangeTrigger = true,
                                        dynamicRetryTimes = 2,
                                        dynamicRetryIntervalMs = 1000L
                                ),
                                */
                                // 规则 7: 天猫
                                /*
                                ExtractionRule(
                                        ruleName = "Tmall",
                                        packageName = "com.tmall.wireless",
                                        activityName =
                                                "com.tmall.wireless.pay.TMPaySuccessActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("支付成功"),
                                                                strategy =
                                                                        SimpleOffset(
                                                                                offset = 0,
                                                                                useExactMatch =
                                                                                        false
                                                                        )
                                                        )
                                                ),
                                        paymentRules = emptyList(),
                                        hasPaymentInfo = false,
                                        continueOnContentFailure = false,
                                        triggerOnEmptyNodes = false,
                                        preFilterByKeywords = true
                                )
                                 */
                                )
        }

        private val json = Json {
                isLenient = true
                ignoreUnknownKeys = true
                prettyPrint = BuildConfig.DEBUG
                encodeDefaults = true
        }

        /** 获取日志级别 Flow，流出的数据类型是 AppLogLevel 枚举 */
        val logLevelFlow: Flow<AppLogLevel> =
                context.configDataStore
                        .data
                        .map { preferences ->
                                val priority =
                                        preferences[KEY_LOG_LEVEL] ?: AppLogLevel.DEFAULT.priority
                                AppLogLevel.fromPriority(priority)
                        }
                        .distinctUntilChanged()

        /** 获取当前日志级别 (一次性) */
        suspend fun getLogLevel(): AppLogLevel {
                val priority =
                        context.configDataStore
                                .data
                                .map { it[KEY_LOG_LEVEL] ?: AppLogLevel.DEFAULT.priority }
                                .first()
                return AppLogLevel.fromPriority(priority)
        }

        /** 设置日志级别，传入枚举 */
        suspend fun putLogLevel(level: AppLogLevel) {
                context.configDataStore.edit { preferences ->
                        // 存入枚举对应的 priority 整数值
                        preferences[KEY_LOG_LEVEL] = level.priority
                }
        }

        /** 写入 String 值 */
        suspend fun putConfig(key: String, value: String) {
                context.configDataStore.edit { preferences ->
                        preferences[stringPreferencesKey(key)] = value
                }
        }

        /** 读取 String 值，若不存在返回 null */
        suspend fun getConfig(key: String): String? {
                return context.configDataStore
                        .data
                        .map { preferences -> preferences[stringPreferencesKey(key)] }
                        .first()
        }

        /** 写入 List<T> 值。会将 List 转换为 JSON 字符串后存储。 */
        private suspend inline fun <reified T> putGenericList(
                key: Preferences.Key<String>,
                value: List<T>
        ) {
                try {
                        val jsonString = json.encodeToString(value)

                        // DataStore.edit 本身就是保存操作。
                        // edit block 正常结束后，DataStore 会自动持久化到磁盘。
                        context.configDataStore.edit { preferences ->
                                preferences[key] = jsonString
                        }
                } catch (e: SerializationException) {
                        AppLog.e(e) { "配置序列化失败 (Key: ${key.name})" }
                } catch (e: Exception) {
                        AppLog.e(e) { "配置保存失败 (Key: ${key.name})" }
                }
        }

        private suspend fun getStringPreference(key: Preferences.Key<String>): String? {
                return context.configDataStore.data.map { preferences -> preferences[key] }.first()
        }

        private inline fun <reified T> decodeListOrDefault(
                jsonString: String?,
                defaultValue: List<T>,
                keyName: String
        ): List<T> {
                if (jsonString == null) return defaultValue

                return try {
                        json.decodeFromString<List<T>>(jsonString)
                } catch (e: Exception) {
                        AppLog.e(e) { "配置解析失败 (Key: $keyName)，使用默认值。JSON: $jsonString" }
                        defaultValue
                }
        }

        private fun decodeAbPackageConfigOrDefault(jsonString: String?): List<PackageConfigItem> {
                return decodeListOrDefault(
                        jsonString = jsonString,
                        defaultValue = DEFAULT_AB_PACKAGES_CONFIG,
                        keyName = KEY_AB_PACKAGE_CONFIG.name
                )
        }

        private fun decodeNlPackageConfigOrDefault(jsonString: String?): List<PackageConfigItem> {
                return decodeListOrDefault(
                        jsonString = jsonString,
                        defaultValue = DEFAULT_NL_PACKAGES_CONFIG,
                        keyName = KEY_NL_PACKAGE_CONFIG.name
                )
        }

        private fun decodeAllowKeywordsOrDefault(jsonString: String?): List<String> {
                return decodeListOrDefault(
                        jsonString = jsonString,
                        defaultValue = DEFAULT_NL_KEYWORDS,
                        keyName = KEY_NL_STATIC_KEYWORDS.name
                )
        }

        private fun decodeExtractionRulesOrDefault(jsonString: String?): List<ExtractionRule> {
                return decodeListOrDefault(
                        jsonString = jsonString,
                        defaultValue = DEFAULT_AB_EXTRACTION_RULES,
                        keyName = KEY_AB_EXTRACTION_RULES.name
                )
        }

        /** 删除单个配置项 */
        suspend fun removeConfig(key: String) {
                context.configDataStore.edit { preferences ->
                        preferences.remove(stringPreferencesKey(key))
                }
        }

        /** 清空所有配置项 */
        suspend fun clearAllConfig() {
                context.configDataStore.edit { preferences -> preferences.clear() }
        }

        /** 获取 abAllowPackage 配置 */
        suspend fun getAbAllowPackageConfig(): List<PackageConfigItem> {
                return decodeAbPackageConfigOrDefault(getStringPreference(KEY_AB_PACKAGE_CONFIG))
        }

        /** 设置 abAllowPackage 配置 */
        suspend fun putAbAllowPackageConfig(value: List<PackageConfigItem>) {
                putGenericList(KEY_AB_PACKAGE_CONFIG, value)
        }

        /** 获取 nlAllowPackage 配置 */
        suspend fun getNlAllowPackageConfig(): List<PackageConfigItem> {
                return decodeNlPackageConfigOrDefault(getStringPreference(KEY_NL_PACKAGE_CONFIG))
        }

        /** 设置 nlAllowPackage 配置 */
        suspend fun putNlAllowPackageConfig(value: List<PackageConfigItem>) {
                putGenericList(KEY_NL_PACKAGE_CONFIG, value)
        }

        /** 获取允许的关键词列表 */
        suspend fun getAllowKeywords(): List<String> {
                return decodeAllowKeywordsOrDefault(getStringPreference(KEY_NL_STATIC_KEYWORDS))
        }

        /** 设置允许的关键词列表 */
        suspend fun putAllowKeywords(keywords: List<String>) {
                putGenericList(KEY_NL_STATIC_KEYWORDS, keywords)
        }

        /** 获取提取规则配置 */
        suspend fun getExtractionRules(): List<ExtractionRule> {
                return decodeExtractionRulesOrDefault(getStringPreference(KEY_AB_EXTRACTION_RULES))
        }

        /** 设置提取规则配置 */
        suspend fun putExtractionRules(rules: List<ExtractionRule>) {
                putGenericList(KEY_AB_EXTRACTION_RULES, rules)
        }

        /** 获取窗口变化防抖时间（毫秒），若未设置则返回默认值 */
        suspend fun getWindowChangeDebounceMs(): Long {
                return context.configDataStore
                        .data
                        .map { preferences ->
                                preferences[KEY_WINDOW_CHANGE_DEBOUNCE_MS]
                                        ?: DEFAULT_WINDOW_CHANGE_DEBOUNCE_MS
                        }
                        .first()
        }

        /** 设置窗口变化防抖时间（毫秒） */
        suspend fun putWindowChangeDebounceMs(value: Long) {
                context.configDataStore.edit { preferences ->
                        preferences[KEY_WINDOW_CHANGE_DEBOUNCE_MS] = value
                }
        }
        /** 获取内容变化防抖时间（毫秒），若未设置则返回默认值 */
        suspend fun getContentChangeDebounceMs(): Long {
                return context.configDataStore
                        .data
                        .map { preferences ->
                                preferences[KEY_CONTENT_CHANGE_DEBOUNCE_MS]
                                        ?: DEFAULT_CONTENT_CHANGE_DEBOUNCE_MS
                        }
                        .first()
        }

        /** 设置内容变化防抖时间（毫秒） */
        suspend fun putContentChangeDebounceMs(value: Long) {
                context.configDataStore.edit { preferences ->
                        preferences[KEY_CONTENT_CHANGE_DEBOUNCE_MS] = value
                }
        }
        /** 获取是否开启内容变化监听 */
        suspend fun getEnableWindowContentChange(): Boolean {
                return context.configDataStore
                        .data
                        .map { preferences ->
                                preferences[KEY_ENABLE_WINDOW_CONTENT_CHANGE]
                                        ?: DEFAULT_ENABLE_WINDOW_CONTENT_CHANGE
                        }
                        .first()
        }

        /** 设置是否开启内容变化监听 */
        suspend fun putEnableWindowContentChange(value: Boolean) {
                context.configDataStore.edit { preferences ->
                        preferences[KEY_ENABLE_WINDOW_CONTENT_CHANGE] = value
                }
        }

        // flow，触发配置刷新
        val serviceConfigFlow: Flow<ServiceConfig> =
                context.configDataStore
                        .data
                        .map { preferences ->
                                val allowedPackages =
                                        decodeAbPackageConfigOrDefault(
                                                preferences[KEY_AB_PACKAGE_CONFIG]
                                        )

                                val allowedPackageNames =
                                        allowedPackages
                                                .filter { it.isAllowed }
                                                .map { it.packageName }
                                                .toSet()

                                val rulesList =
                                        decodeExtractionRulesOrDefault(
                                                preferences[KEY_AB_EXTRACTION_RULES]
                                        )

                                val rulesMap = rulesList.groupBy { it.packageName }

                                val winDebounce =
                                        preferences[KEY_WINDOW_CHANGE_DEBOUNCE_MS]
                                                ?: DEFAULT_WINDOW_CHANGE_DEBOUNCE_MS
                                val contentDebounce =
                                        preferences[KEY_CONTENT_CHANGE_DEBOUNCE_MS]
                                                ?: DEFAULT_CONTENT_CHANGE_DEBOUNCE_MS
                                val enableContent =
                                        preferences[KEY_ENABLE_WINDOW_CONTENT_CHANGE]
                                                ?: DEFAULT_ENABLE_WINDOW_CONTENT_CHANGE

                                ServiceConfig(
                                        allowedPackageNames = allowedPackageNames,
                                        extractionRules = rulesMap,
                                        windowChangeDebounceMs = winDebounce,
                                        contentChangeDebounceMs = contentDebounce,
                                        isContentChangeEnabled = enableContent,
                                )
                        }
                        .distinctUntilChanged()

        val notificationConfigFlow: Flow<NotificationConfig> =
                context.configDataStore
                        .data
                        .map { preferences ->
                                val allowedPackagesList =
                                        decodeNlPackageConfigOrDefault(
                                                preferences[KEY_NL_PACKAGE_CONFIG]
                                        )

                                val allowedPackageSet =
                                        allowedPackagesList
                                                .filter { it.isAllowed }
                                                .map { it.packageName }
                                                .toSet()

                                val keywordsList =
                                        decodeAllowKeywordsOrDefault(
                                                preferences[KEY_NL_STATIC_KEYWORDS]
                                        )

                                NotificationConfig(allowedPackageSet, keywordsList)
                        }
                        .distinctUntilChanged()
}
