package com.rkroom.simple_account

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// 配置项数据类
@Serializable
data class PackageConfigItem(val packageName: String, val appName: String, val isAllowed: Boolean)

/** 数据存放在 /data/data/<your.package>/shared_prefs/ConfigPreferences.xml */
class ConfigPreferencesManager private constructor(context: Context) {

    companion object {
        private const val PREFS_NAME = "ConfigPreferences" // SharedPreferences 文件名
        @Volatile private var instance: ConfigPreferencesManager? = null

        // SharedPreferences 的键常量
        private const val KEY_AB_PACKAGE_CONFIG = "abPackageConfig"
        private const val KEY_NL_PACKAGE_CONFIG = "nlPackageConfig"
        private const val KEY_NL_STATIC_KEYWORDS = "nlKeywords"

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
                        )
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

        private val DEFAULT_NL_KEYWORDS: List<String> = listOf("交易", "支付")

        /** 获取单例实例 */
        fun getInstance(context: Context): ConfigPreferencesManager =
                instance
                        ?: synchronized(this) {
                            instance
                                    ?: ConfigPreferencesManager(context.applicationContext).also {
                                        instance = it
                                    }
                        }
    }

    private val prefs: SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val json = Json {
        isLenient = true
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    /** 写入 String 值 */
    fun putConfig(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    /** 读取 String 值，若不存在返回 null */
    fun getConfig(key: String): String? {
        return prefs.getString(key, null)
    }

    /** 写入 List<T> 值。 会将 List 转换为 JSON 字符串后存储。 */
    private inline fun <reified T> putGenericList(key: String, value: List<T>) {
        try {
            val jsonString = json.encodeToString(value)
            prefs.edit().putString(key, jsonString).apply()
        } catch (e: SerializationException) {
            // Log 
        } catch (e: Exception) {
            // Log 
        }
    }

    /** 读取 List<T> 值。 会将存储的 JSON 字符串转换回 List。 若不存在或转换失败，则返回 null。 */
    private inline fun <reified T> getGenericList(key: String): List<T>? {
        val jsonString = prefs.getString(key, null)
        return if (jsonString != null) {
            try {
                json.decodeFromString<List<T>>(jsonString)
            } catch (e: SerializationException) {
                null // Log 
            } catch (e: IllegalArgumentException) {
                null // Log 
            } catch (e: Exception) {
                null // Log 
            }
        } else {
            null
        }
    }

    /** 写入 List<PackageConfigItem> 值。 会将 List 转换为 JSON 字符串后存储。 */
    fun putConfigList(key: String, value: List<PackageConfigItem>) { // 方法名保持，参数类型更新
        putGenericList(key, value)
    }

    /** 读取 List<PackageConfigItem> 值。 会将存储的 JSON 字符串转换回 List。 若不存在或转换失败，则返回 null。 */
    fun getConfigList(key: String): List<PackageConfigItem>? {
        return getGenericList<PackageConfigItem>(key)
    }

    /** 删除单个配置项 */
    fun removeConfig(key: String) {
        prefs.edit().remove(key).apply()
    }

    /**
     * 清空所有配置项
     * @return 被删除的条目数
     */
    fun clearAllConfig(): Int {
        val allEntries = prefs.all
        val count = allEntries.size
        if (count == 0) {
            return 0
        }
        prefs.edit().clear().apply()
        return count
    }

    /** 获取 abAllowPackage 配置。 如果未设置，则返回预定义列表。 */
    fun getAbAllowPackageConfig(): List<PackageConfigItem> {
        return getConfigList(KEY_AB_PACKAGE_CONFIG) ?: DEFAULT_AB_PACKAGES_CONFIG
    }

    /** 设置 abAllowPackage 配置。 */
    fun putAbAllowPackageConfig(value: List<PackageConfigItem>) {
        putConfigList(KEY_AB_PACKAGE_CONFIG, value)
    }

    /** 获取 nlAllowPackage 配置。 如果未设置，则返回预定义列表。 */
    fun getNlAllowPackageConfig(): List<PackageConfigItem> {
        return getConfigList(KEY_NL_PACKAGE_CONFIG) ?: DEFAULT_NL_PACKAGES_CONFIG
    }

    /** 设置 nlAllowPackage 配置。 */
    fun putNlAllowPackageConfig(value: List<PackageConfigItem>) {
        putConfigList(KEY_NL_PACKAGE_CONFIG, value)
    }

    /** 获取静态允许的关键词列表。 如果未设置或读取失败，则返回预定义的默认列表。 */
    fun getAllowKeywords(): List<String> {
        return getGenericList<String>(KEY_NL_STATIC_KEYWORDS) ?: DEFAULT_NL_KEYWORDS
    }

    /**
     * 设置静态允许的关键词列表。
     * @param keywords 要保存的关键词列表。
     */
    fun putAllowKeywords(keywords: List<String>) {
        putGenericList(KEY_NL_STATIC_KEYWORDS, keywords)
    }
}
