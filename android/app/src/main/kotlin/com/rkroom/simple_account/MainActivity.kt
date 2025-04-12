package com.rkroom.simple_account

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.pm.PackageManager;
import android.provider.MediaStore
import android.content.ContentValues
import android.os.Environment
import android.os.Build
import java.io.File 
import android.net.Uri

import android.app.ActivityManager
import android.content.Context
import android.os.Process

class MainActivity: FlutterActivity(){


    private fun createDownloadUri(fileName: String, mimeType: String): Uri? {
        val contentValues = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.DATE_ADDED, System.currentTimeMillis() / 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
        }
        return applicationContext.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
    }

    private fun getDownloadFilePath(uri: Uri, defaultFileName: String): String {
        val projection = arrayOf(
            MediaStore.Downloads.DISPLAY_NAME,
            MediaStore.Downloads.RELATIVE_PATH
        )
        val cursor = applicationContext.contentResolver.query(uri, projection, null, null, null)
        if (cursor != null) {
            cursor.use { c ->
                if (c.moveToFirst()) {
                    val displayName = c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME))
                    val relativePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        c.getString(c.getColumnIndexOrThrow(MediaStore.Downloads.RELATIVE_PATH))
                            ?: Environment.DIRECTORY_DOWNLOADS
                    } else {
                        Environment.DIRECTORY_DOWNLOADS
                    }
                    // 清理路径格式：去掉末尾的斜杠，并处理连续斜杠问题
                    val cleanPath = relativePath.removeSuffix("/").replace("//", "/")
                    return "$cleanPath/$displayName"
                }
            }
        }
        return "${Environment.DIRECTORY_DOWNLOADS}/$defaultFileName"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 初始化 MethodChannel 并关联到 MyNotificationListenerService
        MyNotificationListenerService.channel = MethodChannel(
            flutterEngine!!.dartExecutor.binaryMessenger,
            "notification_listener"
        )

        // 设置 MethodChannel 的处理器
        MyNotificationListenerService.channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "checkNotificationPermission" -> {
                    val hasPermission = MyNotificationListenerService.isNotificationListenerEnabled(this)
                    result.success(hasPermission)
                }
                "minimizeApp" -> {
                    moveTaskToBack(false)
                }
                "getBills" -> {
                    val sharedPreferencesManager = SharedPreferencesManager.getInstance(this)
                    result.success(sharedPreferencesManager.getBills())
                }
                "clearBills" -> { 
                    result.success(SharedPreferencesManager.getInstance(this).clearBills())
                }
                "delBill" -> {
                    val index = call.argument<Int>("index")
                    if (index != null) {
                        SharedPreferencesManager.getInstance(this).delBill(index)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Index is null", false)
                    }
                    
                }

                "copyToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")

                    if (sourcePath == null || fileName == null) {
                        result.error("INVALID_ARGUMENTS", "sourcePath 或 fileName 为空", null)
                    } else {
                        val uri = createDownloadUri(fileName, "application/octet-stream")
                        if (uri == null) {
                            result.error("UNAVAILABLE", "无法创建导出文件", null)
                        } else {
                            try {
                                applicationContext.contentResolver.openOutputStream(uri)?.use { outputStream ->
                                    File(sourcePath).inputStream().use { inputStream ->
                                        inputStream.copyTo(outputStream)
                                    }
                                }
                                result.success(getDownloadFilePath(uri, fileName))
                            } catch (e: Exception) {
                                result.error("IO_ERROR", "文件复制失败: ${e.message}", null)
                            }
                        }
                    }
                }

                "exportJsonToDownloads" -> {
                    val fileContent = call.argument<String>("fileContent")
                    val fileName = call.argument<String>("fileName")

                    if (fileContent == null || fileName == null) {
                        result.error("INVALID_ARGUMENTS", "fileContent 或 fileName 为空", null)
                    } else {
                        val uri = createDownloadUri(fileName, "application/json")
                        if (uri == null) {
                            result.error("UNAVAILABLE", "无法创建导出文件", null)
                        } else {
                            try {
                                applicationContext.contentResolver.openOutputStream(uri)?.use { outputStream ->
                                    outputStream.write(fileContent.toByteArray())
                                }
                                result.success(getDownloadFilePath(uri, fileName))
                            } catch (e: Exception) {
                                result.error("IO_ERROR", "文件写入失败: ${e.message}", null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()

            }
        }

        if (MyNotificationListenerService.isNotificationListenerEnabled(this)) {
            //NotificationListenerService被系统退出后再次启动不会bindService
            //检测服务是否被Bind，若否则重启服务，触发reBind
            //ensureCollectorRunning方法可能会失败
            if (ensureCollectorRunning(this) == false){
                restartNotificationListenerService()
            }

        }

    }

    /*
    override fun onResume(){
        super.onResume();
    }
    */
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == MyNotificationListenerService.PERMISSION_REQUEST_CODE) {
            if (MyNotificationListenerService.isNotificationListenerEnabled(this)) {
                Toast.makeText(this, "权限已授予", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "请授予读取通知的权限", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun restartNotificationListenerService() {
        val pm = packageManager
        val componentName = ComponentName(this, MyNotificationListenerService::class.java)

        // Disable the service
        pm.setComponentEnabledSetting(componentName,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP)

        // Enable the service
        pm.setComponentEnabledSetting(componentName,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP)
    }

    private fun requestNotificationPermission() {
        if (!MyNotificationListenerService.isNotificationListenerEnabled(this)) {
            val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            startActivityForResult(intent, MyNotificationListenerService.PERMISSION_REQUEST_CODE)
        } else {
            Toast.makeText(this, "权限已授予", Toast.LENGTH_SHORT).show()
        }
    }

    //getSystemService在部分版本（API26）已弃用，故此该方法并非在所有系统上都能使用
    //可考虑采用某些方法绕过系统限制，例如：https://github.com/rkroom/RestrictionBypass ，https://github.com/tiann/FreeReflection
    //For backwards compatibility, getRunningServices will still return the caller's own services.
    private fun ensureCollectorRunning(context: Context): Boolean {

        val collectorComponent = ComponentName(context, MyNotificationListenerService::class.java)
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        var collectorRunning = false

        val runningServices = manager.getRunningServices(Int.MAX_VALUE)

        if (runningServices.isNullOrEmpty()) return false

        for (service in runningServices) {
            if (service.service == collectorComponent && service.pid == Process.myPid()) {
                collectorRunning = true
                break  // 提前退出循环
            }
        }

        return collectorRunning
    }


}
