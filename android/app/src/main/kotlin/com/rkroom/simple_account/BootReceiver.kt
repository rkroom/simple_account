package com.rkroom.simple_account

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            if (MyNotificationListenerService.isNotificationListenerEnabled(context)) {
                val serviceIntent = Intent(context, MyNotificationListenerService::class.java)
                context.startService(serviceIntent)
            }
            if (MyAccessibilityService.isAccessibilityServiceEnabled(context)) {
                val serviceIntent = Intent(context, MyAccessibilityService::class.java)
                context.startService(serviceIntent)
            }
        }
    }
}
