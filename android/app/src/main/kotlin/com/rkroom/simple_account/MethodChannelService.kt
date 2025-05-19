package com.rkroom.simple_account

import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MethodChannelService {

    companion object {
        private const val CHANNEL_NAME = "channel_listener"

        fun registerMethodCallHandler(activity: MainActivity, binaryMessenger: BinaryMessenger) {
            val currentChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

            currentChannel.setMethodCallHandler { call, result ->
                // 在开头获取两个 Manager 的实例
                val configManager = ConfigPreferencesManager.getInstance(activity)
                val sharedPreferencesManager = SharedPreferencesManager.getInstance(activity)

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
                        result.success(sharedPreferencesManager.getBills())
                    }
                    "clearBills" -> {
                        result.success(sharedPreferencesManager.clearBills())
                    }
                    "delBill" -> {
                        val index = call.argument<Int>("index")
                        if (index != null) {
                            sharedPreferencesManager.delBill(index)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Index is null", null)
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
                                result.error("UNAVAILABLE", "Cannot create export file URI", null)
                            } else {
                                try {
                                    activity.applicationContext.contentResolver.openOutputStream(
                                                    uri
                                            )
                                            ?.use { outputStream ->
                                                File(sourcePath).inputStream().use { inputStream ->
                                                    inputStream.copyTo(outputStream)
                                                }
                                            }
                                    result.success(getDownloadFilePath(activity, uri, fileName))
                                } catch (e: Exception) {
                                    result.error("IO_ERROR", "File copy failed: ${e.message}", null)
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
                                result.error("UNAVAILABLE", "Cannot create export file URI", null)
                            } else {
                                try {
                                    activity.applicationContext.contentResolver.openOutputStream(
                                                    uri
                                            )
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
                        val count = configManager.clearAllConfig()
                        result.success(count)
                    }
                    "putConfigList" -> {
                        val key = call.argument<String>("key")
                        val rawValue = call.argument<List<Map<String, Any?>>>("value")

                        if (key != null && rawValue != null) {
                            try {
                                val packageConfigItems = convertToPackageConfigItems(rawValue)
                                configManager.putConfigList(key, packageConfigItems)
                                result.success(null)
                            } catch (e: ClassCastException) {
                                result.error(
                                        "INVALID_ARGUMENT",
                                        "键 '$key' 的参数 'value' 不是预期的 List<Map<String, Any?>> 类型，或其内部项目不是 Map: ${e.message}",
                                        null
                                )
                            } catch (e: IllegalArgumentException) {
                                result.error("INVALID_ARGUMENT", e.message, null)
                            } catch (e: Exception) {
                                result.error(
                                        "PUT_CONFIG_LIST_FAILED",
                                        "为键 '$key' 保存配置列表失败: ${e.message}",
                                        null
                                )
                            }
                        } else {
                            val nullArg = if (key == null) "key" else "value"
                            result.error(
                                    "INVALID_ARGUMENT",
                                    "调用 putConfigList 时，参数 '$nullArg' 为空。",
                                    null
                            )
                        }
                    }
                    "getConfigList" -> {
                        val key = call.argument<String>("key")
                        if (key != null) {
                            try {
                                val listValueFromManager = configManager.getConfigList(key)
                                val transportableList =
                                        listValueFromManager!!.map { item ->
                                            mapOf(
                                                    "packageName" to item.packageName,
                                                    "appName" to item.appName,
                                                    "isAllowed" to item.isAllowed
                                            )
                                        }
                                result.success(transportableList)
                            } catch (e: Exception) {
                                result.error(
                                        "GET_CONFIG_LIST_FAILED",
                                        "为键 '$key' 获取配置列表失败: ${e.message}",
                                        null
                                )
                            }
                        } else {
                            result.error(
                                    "INVALID_ARGUMENT",
                                    "调用 getConfigList 时，参数 'key' 为空。",
                                    null
                            )
                        }
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
                                MyAccessibilityService.triggerRefreshAllowedPackagesCache(activity)
                                result.success(null)
                            } catch (e: ClassCastException) {
                                result.error(
                                        "INVALID_ARGUMENT",
                                        "参数 'value' 不是预期的 List<Map<String, Any?>> 类型，或其内部项目不是 Map (putAbAllowPackageConfig): ${e.message}",
                                        null
                                )
                            } catch (e: IllegalArgumentException) {
                                result.error("INVALID_ARGUMENT", e.message, null)
                            } catch (e: Exception) {
                                result.error(
                                        "PUT_AB_CONFIG_FAILED",
                                        "保存 AbAllowPackageConfig 失败: ${e.message}",
                                        null
                                )
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
                                MyNotificationListenerService.notifyConfigurationChanged(activity)
                                result.success(null)
                            } catch (e: ClassCastException) {
                                result.error(
                                        "INVALID_ARGUMENT",
                                        "参数 'value' 不是预期的 List<Map<String, Any?>> 类型，或其内部项目不是 Map (putNlAllowPackageConfig): ${e.message}",
                                        null
                                )
                            } catch (e: IllegalArgumentException) {
                                result.error("INVALID_ARGUMENT", e.message, null)
                            } catch (e: Exception) {
                                result.error(
                                        "PUT_NL_CONFIG_FAILED",
                                        "保存 NlAllowPackageConfig 失败: ${e.message}",
                                        null
                                )
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
                            result.error("GET_KEYWORDS_FAILED", "获取允许的关键词列表失败: ${e.message}", null)
                        }
                    }
                    "putAllowKeywords" -> {
                        val keywords = call.argument<List<String>>("keywords")
                        if (keywords != null) {
                            try {
                                configManager.putAllowKeywords(keywords)
                                MyNotificationListenerService.notifyConfigurationChanged(activity)
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
                    else -> result.notImplemented()
                }
            }
        }
    }
}
