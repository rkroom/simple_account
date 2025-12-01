package com.rkroom.simple_account

import android.content.Context
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

// 获取 DataStore 实例
private val Context.configDataStore: DataStore<Preferences> by
        preferencesDataStore(name = "ConfigPreferences")

@Serializable
data class PackageConfigItem(val packageName: String, val appName: String, val isAllowed: Boolean)
/** 辅助功能服务配置 */
data class ServiceConfig(
        val allowedPackageNames: Set<String>,
        val extractionRules: Map<String, List<ExtractionRule>>,
        val transactionCooldownMs: Long,
        val windowChangeDebounceMs: Long,
        val contentChangeDebounceMs: Long,
        val isContentChangeEnabled: Boolean,
        val maxContentTriggerTimes: Int
)

/** 通知监听服务配置 */
data class NotificationConfig(
        val allowedPackages: Set<String>, // 使用 Set 优化查找
        val keywords: List<String>
)

/** 提取策略的密封接口 */
@Serializable sealed interface ExtractionStrategy

/**
 * 策略1: 简单偏移量提取
 * @param offset 偏移量
 * @param useExactMatch 是否要求关键字完全匹配
 */
@Serializable
@SerialName("SimpleOffset")
data class SimpleOffset(val offset: Int, val useExactMatch: Boolean = false) : ExtractionStrategy

/**
 * 策略2: 条件偏移量提取
 * @param checkOffset 条件节点的偏移量
 * @param expectedText 条件节点应包含的文本 (例如 "￥")
 * @param targetOffset 满足条件时，目标数据节点的偏移量
 */
@Serializable
@SerialName("ConditionalOffset")
data class ConditionalOffset(
        val checkOffset: Int,
        val expectedTexts: List<String>,
        val targetOffset: Int
) : ExtractionStrategy

/** 策略3: 文本拼接 */
@Serializable
@SerialName("Concatenate")
data class Concatenate(val parts: List<ConcatPart>) : ExtractionStrategy

/** 定义拼接的各个部分 */
@Serializable sealed interface ConcatPart

@Serializable
@SerialName("Literal")
data class Literal(val text: String) : ConcatPart // 静态文本

@Serializable
@SerialName("NodeText")
data class NodeText(val offset: Int) : ConcatPart // 动态节点文本

/** 包含了关键字和具体执行策略的详细规则 */
@Serializable
data class RuleDetail(val keywords: List<String>, val strategy: ExtractionStrategy) {
        // 使用 lazy 缓存 Set，避免每次提取时重复创建
        val keywordsSet: Set<String> by lazy(LazyThreadSafetyMode.PUBLICATION) { keywords.toSet() }
}

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
        val ruleName: String,
        val packageName: String,
        val activityName: String,
        // 页面复杂后考虑合并为正则，并进行正则匹配
        val contentRules: List<RuleDetail>, // 使用List实现回退
        val paymentRules: List<RuleDetail>, // 使用List实现回退
        val continueOnContentFailure: Boolean = false,
        val triggerOnEmptyNodes: Boolean = false,
        val preFilterByKeywords: Boolean = false,
        val allowContentChangeTrigger: Boolean = false,
        val hasPaymentInfo: Boolean = true
)

/**
 * 使用 DataStore-Preferences 管理应用配置 数据存放在
 * /data/data/<your.package>/files/datastore/ConfigPreferences.pb
 */
class ConfigDataStoreManager private constructor(context: Context) {
        private val context = context.applicationContext

        companion object {
                @Volatile private var instance: ConfigDataStoreManager? = null

                // 常量
                private val KEY_AB_PACKAGE_CONFIG = stringPreferencesKey("abPackageConfig")
                private val KEY_NL_PACKAGE_CONFIG = stringPreferencesKey("nlPackageConfig")
                private val KEY_NL_STATIC_KEYWORDS = stringPreferencesKey("nlKeywords")
                private val KEY_AB_EXTRACTION_RULES = stringPreferencesKey("abExtractionRules")
                private val KEY_TRANSACTION_COOLDOWN_MS =
                        longPreferencesKey("transactionCooldownMs")
                private val KEY_WINDOW_CHANGE_DEBOUNCE_MS =
                        longPreferencesKey("windowChangeDebounceMs")
                private val KEY_CONTENT_CHANGE_DEBOUNCE_MS =
                        longPreferencesKey("contentChangeDebounceMs")
                private val KEY_MAX_CONTENT_TRIGGER_TIMES =
                        intPreferencesKey("maxContentTriggerTimes")
                private const val DEFAULT_TRANSACTION_COOLDOWN_MS = 120000L
                private const val DEFAULT_WINDOW_CHANGE_DEBOUNCE_MS = 500L
                private const val DEFAULT_CONTENT_CHANGE_DEBOUNCE_MS = 500L
                private const val DEFAULT_MAX_CONTENT_TRIGGER_TIMES = 2
                private val KEY_ENABLE_WINDOW_CONTENT_CHANGE =
                        booleanPreferencesKey("enableWindowContentChange")
                private const val DEFAULT_ENABLE_WINDOW_CONTENT_CHANGE = false

                // 默认值
                private val DEFAULT_AB_PACKAGES_CONFIG: List<PackageConfigItem> =
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
                                ),
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
                                        paymentRules = emptyList()
                                ),

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
                                        preFilterByKeywords = true
                                ),
                                // 规则 3: 支付宝
                                ExtractionRule(
                                        ruleName = "Alipay NResPage",
                                        packageName = "com.eg.android.AlipayGphone",
                                        activityName =
                                                "com.alipay.android.phone.businesscommon.ucdp.nfc.activity.NResPageActivity",
                                        contentRules =
                                                listOf(
                                                        RuleDetail(
                                                                keywords = listOf("支付成功"),
                                                                strategy = SimpleOffset(offset = 3)
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
                                                        // 第一个尝试的规则: 检查"￥"符号并拼接
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
                                                        // 如果上面失败，则回退到这个简单规则
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
                                        allowContentChangeTrigger = true
                                ),
                                // 规则 7: 天猫
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
                                        continueOnContentFailure = false,
                                        triggerOnEmptyNodes = false,
                                        preFilterByKeywords = true
                                )
                        )

                fun getInstance(context: Context): ConfigDataStoreManager {
                        return instance
                                ?: synchronized(this) {
                                        instance
                                                ?: ConfigDataStoreManager(context).also {
                                                        instance = it
                                                }
                                }
                }
        }

        private val json = Json {
                isLenient = true
                ignoreUnknownKeys = true
                prettyPrint = BuildConfig.DEBUG
                encodeDefaults = true
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
                        context.configDataStore.edit { preferences ->
                                preferences[key] = jsonString
                        }
                } catch (e: SerializationException) {
                        // Log
                }
        }

        /** 读取 List<T> 值。若不存在或转换失败，则返回 null。 */
        private suspend inline fun <reified T> getGenericList(
                key: Preferences.Key<String>
        ): List<T>? {
                val jsonString =
                        context.configDataStore.data.map { preferences -> preferences[key] }.first()
                return if (jsonString != null) {
                        try {
                                json.decodeFromString<List<T>>(jsonString)
                        } catch (e: Exception) {
                                null // Log
                        }
                } else {
                        null
                }
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
                return getGenericList<PackageConfigItem>(KEY_AB_PACKAGE_CONFIG)
                        ?: DEFAULT_AB_PACKAGES_CONFIG
        }

        /** 设置 abAllowPackage 配置 */
        suspend fun putAbAllowPackageConfig(value: List<PackageConfigItem>) {
                putGenericList(KEY_AB_PACKAGE_CONFIG, value)
        }

        /** 获取 nlAllowPackage 配置 */
        suspend fun getNlAllowPackageConfig(): List<PackageConfigItem> {
                return getGenericList<PackageConfigItem>(KEY_NL_PACKAGE_CONFIG)
                        ?: DEFAULT_NL_PACKAGES_CONFIG
        }

        /** 设置 nlAllowPackage 配置 */
        suspend fun putNlAllowPackageConfig(value: List<PackageConfigItem>) {
                putGenericList(KEY_NL_PACKAGE_CONFIG, value)
        }

        /** 获取允许的关键词列表 */
        suspend fun getAllowKeywords(): List<String> {
                return getGenericList<String>(KEY_NL_STATIC_KEYWORDS) ?: DEFAULT_NL_KEYWORDS
        }

        /** 设置允许的关键词列表 */
        suspend fun putAllowKeywords(keywords: List<String>) {
                putGenericList(KEY_NL_STATIC_KEYWORDS, keywords)
        }

        /** 获取提取规则配置 */
        suspend fun getExtractionRules(): List<ExtractionRule> {
                return getGenericList<ExtractionRule>(KEY_AB_EXTRACTION_RULES)
                        ?: DEFAULT_AB_EXTRACTION_RULES
        }

        /** 设置提取规则配置 */
        suspend fun putExtractionRules(rules: List<ExtractionRule>) {
                putGenericList(KEY_AB_EXTRACTION_RULES, rules)
        }

        /** 获取交易冷却时间（毫秒），若未设置则返回默认值 */
        suspend fun getTransactionCooldownMs(): Long {
                return context.configDataStore
                        .data
                        .map { preferences ->
                                preferences[KEY_TRANSACTION_COOLDOWN_MS]
                                        ?: DEFAULT_TRANSACTION_COOLDOWN_MS
                        }
                        .first()
        }

        /** 设置交易冷却时间（毫秒） */
        suspend fun putTransactionCooldownMs(value: Long) {
                context.configDataStore.edit { preferences ->
                        preferences[KEY_TRANSACTION_COOLDOWN_MS] = value
                }
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
                                val allowedPackagesJson = preferences[KEY_AB_PACKAGE_CONFIG]
                                val allowedPackages =
                                        if (allowedPackagesJson != null) {
                                                try {
                                                        json.decodeFromString<
                                                                List<PackageConfigItem>>(
                                                                allowedPackagesJson
                                                        )
                                                } catch (e: Exception) {
                                                        DEFAULT_AB_PACKAGES_CONFIG
                                                }
                                        } else {
                                                DEFAULT_AB_PACKAGES_CONFIG
                                        }

                                val allowedPackageNames =
                                        allowedPackages
                                                .filter { it.isAllowed }
                                                .map { it.packageName }
                                                .toSet()

                                val rulesJson = preferences[KEY_AB_EXTRACTION_RULES]
                                val rulesList =
                                        if (rulesJson != null) {
                                                try {
                                                        json.decodeFromString<List<ExtractionRule>>(
                                                                rulesJson
                                                        )
                                                } catch (e: Exception) {
                                                        DEFAULT_AB_EXTRACTION_RULES
                                                }
                                        } else {
                                                DEFAULT_AB_EXTRACTION_RULES
                                        }
                                val rulesMap = rulesList.groupBy { it.packageName }

                                val cooldown =
                                        preferences[KEY_TRANSACTION_COOLDOWN_MS]
                                                ?: DEFAULT_TRANSACTION_COOLDOWN_MS
                                val winDebounce =
                                        preferences[KEY_WINDOW_CHANGE_DEBOUNCE_MS]
                                                ?: DEFAULT_WINDOW_CHANGE_DEBOUNCE_MS
                                val contentDebounce =
                                        preferences[KEY_CONTENT_CHANGE_DEBOUNCE_MS]
                                                ?: DEFAULT_CONTENT_CHANGE_DEBOUNCE_MS
                                val enableContent =
                                        preferences[KEY_ENABLE_WINDOW_CONTENT_CHANGE]
                                                ?: DEFAULT_ENABLE_WINDOW_CONTENT_CHANGE
                                val maxTriggerTimes =
                                        preferences[KEY_MAX_CONTENT_TRIGGER_TIMES]
                                                ?: DEFAULT_MAX_CONTENT_TRIGGER_TIMES

                                ServiceConfig(
                                        allowedPackageNames = allowedPackageNames,
                                        extractionRules = rulesMap,
                                        transactionCooldownMs = cooldown,
                                        windowChangeDebounceMs = winDebounce,
                                        contentChangeDebounceMs = contentDebounce,
                                        isContentChangeEnabled = enableContent,
                                        maxContentTriggerTimes = maxTriggerTimes
                                )
                        }
                        .distinctUntilChanged()

        val notificationConfigFlow: Flow<NotificationConfig> =
                context.configDataStore
                        .data
                        .map { preferences ->
                                val allowedPackagesJson = preferences[KEY_NL_PACKAGE_CONFIG]
                                val allowedPackagesList =
                                        if (allowedPackagesJson != null) {
                                                try {
                                                        json.decodeFromString<
                                                                List<PackageConfigItem>>(
                                                                allowedPackagesJson
                                                        )
                                                } catch (e: Exception) {
                                                        DEFAULT_NL_PACKAGES_CONFIG
                                                }
                                        } else {
                                                DEFAULT_NL_PACKAGES_CONFIG
                                        }

                                val allowedPackageSet =
                                        allowedPackagesList
                                                .filter { it.isAllowed }
                                                .map { it.packageName }
                                                .toSet()

                                val keywordsJson = preferences[KEY_NL_STATIC_KEYWORDS]
                                val keywordsList =
                                        if (keywordsJson != null) {
                                                try {
                                                        json.decodeFromString<List<String>>(
                                                                keywordsJson
                                                        )
                                                } catch (e: Exception) {
                                                        DEFAULT_NL_KEYWORDS
                                                }
                                        } else {
                                                DEFAULT_NL_KEYWORDS
                                        }

                                NotificationConfig(allowedPackageSet, keywordsList)
                        }
                        .distinctUntilChanged()
}
