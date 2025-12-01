package com.rkroom.simple_account

import android.content.Intent
import android.provider.Settings
import androidx.lifecycle.lifecycleScope
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class MethodChannelService {
    companion object {
        private const val CHANNEL_NAME = "channel_listener"

        private val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        fun registerMethodCallHandler(activity: MainActivity, binaryMessenger: BinaryMessenger) {
            val currentChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

            // 获取新的 DataStore Manager 实例
            val configManager = ConfigDataStoreManager.getInstance(activity)
            val billManager = BillDataStoreManager.getInstance(activity)

            currentChannel.setMethodCallHandler { call, result ->
                // 使用 lifecycleScope 启动协程，因为 DataStore 操作是 suspend 函数
                activity.lifecycleScope.launch {
                    when (call.method) {
                        "requestNotificationPermission" -> {
                            requestNotificationPermission(activity)
                            result.success(null)
                        }
                        "checkNotificationPermission" -> {
                            val hasPermission =
                                    MyNotificationListenerService.isNotificationListenerEnabled(
                                            activity
                                    )
                            result.success(hasPermission)
                        }
                        "minimizeApp" -> {
                            activity.moveTaskToBack(false)
                            result.success(null)
                        }
                        "getBills" -> {
                            result.success(billManager.getBills())
                        }
                        "clearBills" -> {
                            billManager.clearBills()
                            result.success(true)
                        }
                        "delBill" -> {
                            val id = call.argument<String>("id")
                            if (id != null) {
                                billManager.delBill(id)
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGUMENT", "ID is null", null)
                            }
                        }
                        "copyToDownloads" -> {
                            val sourcePath = call.argument<String>("sourcePath")
                            val fileName = call.argument<String>("fileName")

                            if (sourcePath == null || fileName == null) {
                                result.error(
                                        "INVALID_ARGUMENTS",
                                        "sourcePath or fileName is empty",
                                        null
                                )
                            } else {
                                val uri =
                                        createDownloadUri(
                                                activity,
                                                fileName,
                                                "application/octet-stream"
                                        )
                                if (uri == null) {
                                    result.error(
                                            "UNAVAILABLE",
                                            "Cannot create export file URI",
                                            null
                                    )
                                } else {
                                    try {
                                        activity.applicationContext.contentResolver
                                                .openOutputStream(uri)
                                                ?.use { outputStream ->
                                                    File(sourcePath).inputStream().use { inputStream
                                                        ->
                                                        inputStream.copyTo(outputStream)
                                                    }
                                                }
                                        result.success(getDownloadFilePath(activity, uri, fileName))
                                    } catch (e: Exception) {
                                        result.error(
                                                "IO_ERROR",
                                                "File copy failed: ${e.message}",
                                                null
                                        )
                                    }
                                }
                            }
                        }
                        "exportJsonToDownloads" -> {
                            val fileContent = call.argument<String>("fileContent")
                            val fileName = call.argument<String>("fileName")

                            if (fileContent == null || fileName == null) {
                                result.error(
                                        "INVALID_ARGUMENTS",
                                        "fileContent or fileName is empty",
                                        null
                                )
                            } else {
                                val uri = createDownloadUri(activity, fileName, "application/json")
                                if (uri == null) {
                                    result.error(
                                            "UNAVAILABLE",
                                            "Cannot create export file URI",
                                            null
                                    )
                                } else {
                                    try {
                                        activity.applicationContext.contentResolver
                                                .openOutputStream(uri)
                                                ?.use { outputStream ->
                                                    outputStream.write(fileContent.toByteArray())
                                                }
                                        result.success(getDownloadFilePath(activity, uri, fileName))
                                    } catch (e: Exception) {
                                        result.error(
                                                "IO_ERROR",
                                                "File write failed: ${e.message}",
                                                null
                                        )
                                    }
                                }
                            }
                        }
                        "openAccessibilitySettings" -> {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            activity.startActivity(intent)
                            result.success(null)
                        }
                        "isAccessibilityEnabled" -> {
                            val hasPermission =
                                    MyAccessibilityService.isAccessibilityServiceEnabled(activity)
                            result.success(hasPermission)
                        }
                        "putConfig" -> {
                            val key = call.argument<String>("key")
                            val value = call.argument<String>("value")
                            if (key != null && value != null) {
                                configManager.putConfig(key, value)
                                result.success(null)
                            } else {
                                result.error("INVALID_ARGUMENT", "Key or value is null", null)
                            }
                        }
                        "getConfig" -> {
                            val key = call.argument<String>("key")
                            if (key != null) {
                                val value = configManager.getConfig(key)
                                result.success(value)
                            } else {
                                result.error("INVALID_ARGUMENT", "Key is null", null)
                            }
                        }
                        "removeConfig" -> {
                            val key = call.argument<String>("key")
                            if (key != null) {
                                configManager.removeConfig(key)
                                result.success(null)
                            } else {
                                result.error("INVALID_ARGUMENT", "Key is null", null)
                            }
                        }
                        "clearAllConfig" -> {
                            configManager.clearAllConfig()
                            result.success(null)
                        }
                        "getAbAllowPackageConfig" -> {
                            try {
                                val configFromManager = configManager.getAbAllowPackageConfig()
                                val transportableList =
                                        configFromManager.map { item ->
                                            mapOf(
                                                    "packageName" to item.packageName,
                                                    "appName" to item.appName,
                                                    "isAllowed" to item.isAllowed
                                            )
                                        }
                                result.success(transportableList)
                            } catch (e: Exception) {
                                result.error(
                                        "GET_AB_CONFIG_FAILED",
                                        "获取 AbAllowPackageConfig 失败: ${e.message}",
                                        null
                                )
                            }
                        }
                        "putAbAllowPackageConfig" -> {
                            val rawValue = call.argument<List<Map<String, Any?>>>("value")
                            if (rawValue != null) {
                                try {
                                    val packageConfigItems = convertToPackageConfigItems(rawValue)
                                    configManager.putAbAllowPackageConfig(packageConfigItems)
                                    result.success(null)
                                } catch (e: Exception) {
                                    when (e) {
                                        is ClassCastException, is IllegalArgumentException ->
                                                result.error(
                                                        "INVALID_ARGUMENT",
                                                        "参数 'value' 格式错误: ${e.message}",
                                                        null
                                                )
                                        else ->
                                                result.error(
                                                        "PUT_AB_CONFIG_FAILED",
                                                        "保存 AbAllowPackageConfig 失败: ${e.message}",
                                                        null
                                                )
                                    }
                                }
                            } else {
                                result.error(
                                        "INVALID_ARGUMENT",
                                        "调用 putAbAllowPackageConfig 时，参数 'value' 为空。",
                                        null
                                )
                            }
                        }
                        "getNlAllowPackageConfig" -> {
                            try {
                                val configFromManager = configManager.getNlAllowPackageConfig()
                                val transportableList =
                                        configFromManager.map { item ->
                                            mapOf(
                                                    "packageName" to item.packageName,
                                                    "appName" to item.appName,
                                                    "isAllowed" to item.isAllowed
                                            )
                                        }
                                result.success(transportableList)
                            } catch (e: Exception) {
                                result.error(
                                        "GET_NL_CONFIG_FAILED",
                                        "获取 NlAllowPackageConfig 失败: ${e.message}",
                                        null
                                )
                            }
                        }
                        "putNlAllowPackageConfig" -> {
                            val rawValue = call.argument<List<Map<String, Any?>>>("value")
                            if (rawValue != null) {
                                try {
                                    val packageConfigItems = convertToPackageConfigItems(rawValue)
                                    configManager.putNlAllowPackageConfig(packageConfigItems)
                                    result.success(null)
                                } catch (e: Exception) {
                                    when (e) {
                                        is ClassCastException, is IllegalArgumentException ->
                                                result.error(
                                                        "INVALID_ARGUMENT",
                                                        "参数 'value' 格式错误: ${e.message}",
                                                        null
                                                )
                                        else ->
                                                result.error(
                                                        "PUT_NL_CONFIG_FAILED",
                                                        "保存 NlAllowPackageConfig 失败: ${e.message}",
                                                        null
                                                )
                                    }
                                }
                            } else {
                                result.error(
                                        "INVALID_ARGUMENT",
                                        "调用 putNlAllowPackageConfig 时，参数 'value' 为空。",
                                        null
                                )
                            }
                        }
                        "getAllowKeywords" -> {
                            try {
                                val keywords = configManager.getAllowKeywords()
                                result.success(keywords)
                            } catch (e: Exception) {
                                result.error(
                                        "GET_KEYWORDS_FAILED",
                                        "获取允许的关键词列表失败: ${e.message}",
                                        null
                                )
                            }
                        }
                        "putAllowKeywords" -> {
                            val keywords = call.argument<List<String>>("keywords")
                            if (keywords != null) {
                                try {
                                    configManager.putAllowKeywords(keywords)
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error(
                                            "PUT_KEYWORDS_FAILED",
                                            "保存允许的关键词列表失败: ${e.message}",
                                            null
                                    )
                                }
                            } else {
                                result.error(
                                        "INVALID_ARGUMENT",
                                        "调用 putAllowKeywords 时，参数 'keywords' 为空。",
                                        null
                                )
                            }
                        }
                        "getExtractionRules" -> {
                            try {
                                // 1. 获取 ExtractionRule 对象列表
                                val rules = configManager.getExtractionRules()

                                // 2. 将整个列表序列化成一个单独的 JSON 字符串
                                val rulesJsonString = json.encodeToString(rules)

                                // 3. 将完整的 JSON 字符串发送给 Flutter
                                result.success(rulesJsonString)
                            } catch (e: Exception) {
                                result.error("GET_RULES_FAILED", "获取提取规则失败: ${e.message}", null)
                            }
                        }
                        "putExtractionRules" -> {
                            val rulesJson = call.argument<String>("rules")
                            if (rulesJson != null) {
                                try {
                                    val rules =
                                            Json.decodeFromString<List<ExtractionRule>>(rulesJson)
                                    configManager.putExtractionRules(rules)
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error("PUT_RULES_FAILED", "保存提取规则失败: ${e.message}", null)
                                }
                            } else {
                                result.error("INVALID_ARGUMENT", "参数 'rules' 为空。", null)
                            }
                        }
                        "getEnableWindowContentChange" -> {
                            try {
                                val value = configManager.getEnableWindowContentChange()
                                result.success(value)
                            } catch (e: Exception) {
                                result.error(
                                        "GET_CONFIG_FAILED",
                                        "获取 EnableWindowContentChange 失败: ${e.message}",
                                        null
                                )
                            }
                        }
                        "putEnableWindowContentChange" -> {
                            val value = call.argument<Boolean>("value")
                            if (value != null) {
                                try {
                                    configManager.putEnableWindowContentChange(value)
                                    result.success(null)
                                } catch (e: Exception) {
                                    result.error(
                                            "PUT_CONFIG_FAILED",
                                            "保存 EnableWindowContentChange 失败: ${e.message}",
                                            null
                                    )
                                }
                            } else {
                                result.error("INVALID_ARGUMENT", "参数 'value' 为空", null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        }

        /** 将 List<Map<String, Any?>> 转换为 List<PackageConfigItem> */
        private fun convertToPackageConfigItems(
                rawValue: List<Map<String, Any?>>
        ): List<PackageConfigItem> {
            return rawValue.map { map ->
                val packageName =
                        map["packageName"] as? String
                                ?: throw IllegalArgumentException("列表项中缺少或无效的 'packageName'")
                val appName =
                        map["appName"] as? String
                                ?: throw IllegalArgumentException("列表项中缺少或无效的 'appName'")
                val isAllowed =
                        map["isAllowed"] as? Boolean
                                ?: throw IllegalArgumentException("列表项中缺少或无效的 'isAllowed'")
                PackageConfigItem(packageName, appName, isAllowed)
            }
        }
    }
}
