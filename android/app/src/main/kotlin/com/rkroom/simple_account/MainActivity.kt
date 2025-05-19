package com.rkroom.simple_account

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannelService.registerMethodCallHandler(
                this,
                flutterEngine.dartExecutor.binaryMessenger
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        //可能同样需要检查MyAccessibilityService
        if (MyNotificationListenerService.isNotificationListenerEnabled(this)) {
            // NotificationListenerService被系统退出后再次启动不会bindService
            // 检测服务是否被Bind，若否则重启服务，触发reBind
            // ensureCollectorRunning方法可能会失败
            if (ensureCollectorRunning(this) == false) {
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

        pm.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
        )

        pm.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
        )
    }
}
